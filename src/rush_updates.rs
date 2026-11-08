// Windows x64 / RushRemoteUtility only. The service owns this channel.
use hbb_common::{bail, config::Config, log, sodiumoxide::crypto::sign, ResultType};
use sha2::{Digest, Sha256};
use std::{fs, io::{Read, Write}, os::windows::process::CommandExt, path::{Path, PathBuf},
    process::Command, time::{Duration, Instant}};

const RELEASE: &str = include_str!("../rush-release/VERSION");
const PRODUCT: &str = "RushRemoteUtility";
const LIMIT: u64 = 300 * 1024 * 1024;

fn program_files() -> ResultType<PathBuf> {
    Ok(PathBuf::from(std::env::var("ProgramFiles")?))
}

fn maintenance() -> ResultType<PathBuf> {
    Ok(program_files()?.join("RushRemoteUtility Maintenance"))
}

fn report(message: &str) {
    log::info!("Rush update: {}", message);
    if let Ok(dir) = maintenance() {
        let _ = fs::create_dir_all(&dir);
        let _ = fs::write(dir.join("status.txt"), message);
    }
}

fn version(s: &str) -> ResultType<[u32; 3]> {
    let mut out = [0; 3];
    let mut parts = s.split('.');
    for n in &mut out {
        let part = parts.next().unwrap_or("");
        *n = part.parse()?;
        if n.to_string() != part { bail!("Некорректная версия"); }
    }
    if parts.next().is_some() { bail!("Некорректная версия"); }
    Ok(out)
}

#[derive(serde::Deserialize)]
struct Release { product: String, version: String, size: u64, sha256: String }

fn run_script(script: &Path, action: &str) -> ResultType<()> {
    let shell = PathBuf::from(std::env::var("SystemRoot")?)
        .join(r"System32\WindowsPowerShell\v1.0\powershell.exe");
    let out = Command::new(shell).args(["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File"])
        .arg(script).arg(action).creation_flags(0x08000000).output()?;
    if !out.status.success() { bail!("{}: {}", action, String::from_utf8_lossy(&out.stderr)); }
    Ok(())
}

// true = repeat soon (a live session or a pending installation).
fn check(manual: bool) -> ResultType<bool> {
    let base = option_env!("RUSH_UPDATE_URL").unwrap_or("").trim_end_matches('/');
    let pin = option_env!("RUSH_UPDATE_PIN").unwrap_or("");
    if !base.starts_with("https://") || pin.is_empty() {
        bail!("Канал обновлений не настроен при сборке");
    }
    let install = program_files()?.join(PRODUCT);
    if fs::canonicalize(std::env::current_exe()?)? != fs::canonicalize(install.join("RushRemoteUtility.exe"))? {
        bail!("Для автообновления установите клиент в стандартную папку Program Files");
    }
    let dir = maintenance()?;
    fs::create_dir_all(&dir)?;
    // Several interactive Windows sessions may start a mediator concurrently.
    use std::os::windows::fs::OpenOptionsExt;
    let _worker_lock = match fs::OpenOptions::new().create(true).write(true)
        .share_mode(0).open(dir.join("check.lock")) {
        Ok(f) => f,
        Err(e) if e.raw_os_error() == Some(32) => return Ok(true),
        Err(e) => return Err(e.into()),
    };
    if dir.join("pending").exists() || dir.join("previous").exists() {
        return Ok(true);
    }
    let client = reqwest::blocking::Client::builder().https_only(true)
        .timeout(Duration::from_secs(180)).build()?;
    let github_releases = base.starts_with("https://github.com/") && base.ends_with("/releases");
    let manifest_url = if github_releases {
        format!("{base}/latest/download/stable.bin")
    } else {
        format!("{base}/stable.bin")
    };
    let mut envelope = Vec::new();
    client.get(manifest_url).send()?.error_for_status()?
        .take(8193).read_to_end(&mut envelope)?;
    if envelope.len() > 8192 { bail!("Слишком большой манифест"); }
    let key = sign::PublicKey::from_slice(&crate::common::decode64(pin)?)
        .ok_or_else(|| hbb_common::anyhow::anyhow!("Неверный ключ обновлений"))?;
    let data = sign::verify(&envelope, &key).map_err(|_| hbb_common::anyhow::anyhow!("Подпись релиза не прошла проверку"))?;
    let rel: Release = serde_json::from_slice(&data)?;
    if rel.product != "RushRemoteUtility/windows-x64" || rel.size == 0 || rel.size > LIMIT
        || rel.sha256.len()!=64 || !rel.sha256.bytes().all(|b|b.is_ascii_hexdigit()) {
        bail!("Неверный манифест релиза");
    }
    let installed = option_env!("RUSH_RELEASE_VERSION").unwrap_or(RELEASE).trim();
    if version(&rel.version)? <= version(installed)? {
        report(&format!("Установлена актуальная версия {installed}")); return Ok(false);
    }
    if !manual && fs::read_to_string(dir.join("failed.txt")).unwrap_or_default().trim() == rel.version {
        report("Предыдущая попытка установки не удалась. Для повтора нажмите «Проверить обновления»."); return Ok(false);
    }
    if !super::updater::has_no_active_conns() {
        report("Обновление отложено до завершения сеансов"); return Ok(true);
    }
    let script = dir.join("maintain.ps1");
    fs::write(&script, include_bytes!("../rush-release/maintain.ps1"))?;
    let archive = dir.join("package.zip");
    let archive_url = if github_releases {
        format!("{base}/download/v{}/windows-x64.zip",rel.version)
    } else {
        format!("{base}/v{}/windows-x64.zip",rel.version)
    };
    let mut response = client.get(archive_url)
        .send()?.error_for_status()?.take(rel.size+1);
    let mut output = fs::File::create(&archive)?;
    let mut hash = Sha256::new();
    let mut buf=[0;65536];
    let mut size=0u64;
    report(&format!("Загрузка версии {}",rel.version));
    loop {
        let count=response.read(&mut buf)?;
        if count==0 { break; }
        hash.update(&buf[..count]); output.write_all(&buf[..count])?; size+=count as u64;
    }
    output.sync_all()?; drop(output);
    if size != rel.size || format!("{:x}",hash.finalize()) != rel.sha256 {
        bail!("Контрольная сумма обновления не совпала");
    }
    run_script(&script,"Prepare")?;
    if fs::read_to_string(dir.join("staged/rush-version.txt"))?.trim() != rel.version {
        bail!("Версия внутри пакета не совпала с манифестом");
    }
    if !super::updater::has_no_active_conns() {
        report("Установка отложена до завершения сеансов"); return Ok(true);
    }
    report(&format!("Установка версии {}",rel.version));
    run_script(&script,"Queue")?;
    Ok(true)
}

pub(super) fn worker(rx: std::sync::mpsc::Receiver<super::updater::UpdateMsg>) {
    use super::updater::UpdateMsg;
    use std::sync::mpsc::RecvTimeoutError;
    let mut next = Instant::now() + Duration::from_secs(30);
    let mut last = Config::get_option("rush-check-finished");
    let mut manual_retry = false;
    loop {
        let explicit = match rx.recv_timeout(Duration::from_secs(5)) {
            Ok(UpdateMsg::Exit) | Err(RecvTimeoutError::Disconnected) => break,
            Ok(UpdateMsg::CheckUpdate) => true,
            Err(RecvTimeoutError::Timeout) => false,
        };
        let req = Config::get_option("rush-check-request");
        let manual = explicit || (!req.is_empty() && req != last);
        if manual { manual_retry = true; }
        if !manual && (Instant::now() < next ||
            (!manual_retry && !Config::get_bool_option("allow-auto-update"))) { continue; }
        let delay = match check(manual_retry) {
            Ok(true) => 60,
            Ok(false) => { manual_retry=false; 86400 },
            Err(e) => { report(&format!("Ошибка проверки: {e}")); manual_retry=false; 1800 },
        };
        if manual && !req.is_empty() { Config::set_option("rush-check-finished".into(),req.clone()); last=req; }
        next = Instant::now() + Duration::from_secs(delay);
    }
}
