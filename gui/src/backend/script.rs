use std::path::PathBuf;
use std::process::Stdio;
use tokio::process::Command;
use tokio::io::{AsyncBufReadExt, BufReader};

#[derive(Debug, Clone)]
pub struct ScriptOutput {
    pub stdout: String,
    pub stderr: String,
    pub success: bool,
}

/// Get the path to wifi-manager.sh
/// 
/// Resolution order:
/// 1. WIFI_MANAGER_SCRIPT environment variable
/// 2. Relative to executable (for installed/release builds)
/// 3. Current working directory
/// 4. Parent of current working directory
pub fn get_script_path() -> PathBuf {
    // 1. Check environment variable first (highest priority)
    if let Ok(env_path) = std::env::var("WIFI_MANAGER_SCRIPT") {
        let path = PathBuf::from(&env_path);
        if path.exists() {
            return path;
        }
        eprintln!("[WARN] WIFI_MANAGER_SCRIPT set but path not found: {}", env_path);
    }
    
    // 2. Relative to executable (for installed/release builds)
    if let Ok(exe_path) = std::env::current_exe() {
        // From gui/target/debug or gui/target/release -> project root
        let mut path = exe_path.clone();
        path.pop(); // remove binary name
        path.pop(); // remove debug/release
        path.pop(); // remove target
        path.pop(); // remove gui
        path.push("wifi-manager.sh");
        if path.exists() {
            return path;
        }
        
        // Also try: target/debug -> project root (if gui folder is missing)
        let mut path = exe_path;
        path.pop(); // remove binary
        path.pop(); // remove debug/release
        path.pop(); // remove target
        path.push("wifi-manager.sh");
        if path.exists() {
            return path;
        }
    }
    
    // 3. Check current working directory
    if let Ok(cwd) = std::env::current_dir() {
        let mut path = cwd.clone();
        path.push("wifi-manager.sh");
        if path.exists() {
            return path;
        }
        
        // 4. Check parent of current working directory
        path = cwd;
        path.pop();
        path.push("wifi-manager.sh");
        if path.exists() {
            return path;
        }
    }
    
    // Last resort - return relative path and let caller handle missing file
    PathBuf::from("wifi-manager.sh")
}

/// Strip ANSI escape codes from output
fn strip_ansi_codes(s: &str) -> String {
    let mut result = String::new();
    let mut chars = s.chars().peekable();
    
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            // Skip until 'm' (end of ANSI sequence)
            while let Some(&next) = chars.peek() {
                chars.next();
                if next == 'm' {
                    break;
                }
            }
        } else {
            result.push(c);
        }
    }
    result
}

/// Run a wifi-manager.sh command and capture output using direct process execution
pub async fn run_command_in_terminal(cmd: &str) -> Result<ScriptOutput, String> {
    let script_path = get_script_path();
    
    if !script_path.exists() {
        return Err(format!("Script not found at: {:?}\nSet WIFI_MANAGER_SCRIPT environment variable to override.", script_path));
    }
    
    let script_dir = script_path.parent().unwrap_or(&PathBuf::from(".")).to_path_buf();
    
    let mut child = Command::new("bash")
        .arg(&script_path)
        .arg(cmd)
        .current_dir(&script_dir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to spawn process: {}", e))?;
    
    let stdout = child.stdout.take().ok_or("Failed to capture stdout")?;
    let stderr = child.stderr.take().ok_or("Failed to capture stderr")?;
    
    // Read stdout and stderr concurrently
    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);
    
    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();
    
    let mut stdout_output = String::new();
    let mut stderr_output = String::new();
    
    // Collect stdout
    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }
    
    // Collect stderr
    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }
    
    let status = child.wait().await
        .map_err(|e| format!("Failed to wait for process: {}", e))?;
    
    Ok(ScriptOutput {
        stdout: strip_ansi_codes(&stdout_output),
        stderr: strip_ansi_codes(&stderr_output),
        success: status.success(),
    })
}

/// Run command with sudo using pkexec and capture output directly
pub async fn run_sudo_command_in_terminal(cmd: &str) -> Result<ScriptOutput, String> {
    let script_path = get_script_path();
    
    if !script_path.exists() {
        return Err(format!("Script not found at: {:?}\nSet WIFI_MANAGER_SCRIPT environment variable to override.", script_path));
    }
    
    let script_dir = script_path.parent().unwrap_or(&PathBuf::from(".")).to_path_buf();
    let script_path_str = script_path.to_string_lossy().to_string();
    let script_dir_str = script_dir.to_string_lossy().to_string();
    
    // pkexec doesn't preserve working directory, so use sh -c
    let shell_cmd = format!("cd '{}' && bash '{}' {}", script_dir_str, script_path_str, cmd);
    
    let mut child = Command::new("pkexec")
        .arg("sh")
        .arg("-c")
        .arg(&shell_cmd)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to spawn pkexec: {}", e))?;
    
    let stdout = child.stdout.take().ok_or("Failed to capture stdout")?;
    let stderr = child.stderr.take().ok_or("Failed to capture stderr")?;
    
    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);
    
    let mut stdout_lines = stdout_reader.lines();
    let mut stderr_lines = stderr_reader.lines();
    
    let mut stdout_output = String::new();
    let mut stderr_output = String::new();
    
    while let Ok(Some(line)) = stdout_lines.next_line().await {
        stdout_output.push_str(&line);
        stdout_output.push('\n');
    }
    
    while let Ok(Some(line)) = stderr_lines.next_line().await {
        stderr_output.push_str(&line);
        stderr_output.push('\n');
    }
    
    let status = child.wait().await
        .map_err(|e| format!("Failed to wait for pkexec: {}", e))?;
    
    Ok(ScriptOutput {
        stdout: strip_ansi_codes(&stdout_output),
        stderr: strip_ansi_codes(&stderr_output),
        success: status.success(),
    })
}

/// Run a wifi-manager.sh command and return output (silent mode - no terminal)
pub async fn run_command(cmd: &str) -> Result<ScriptOutput, String> {
    // Delegate to the main implementation
    run_command_in_terminal(cmd).await
}

/// Run command with sudo (for install/backup) - silent mode
pub async fn run_sudo_command(cmd: &str) -> Result<ScriptOutput, String> {
    // Delegate to the main implementation
    run_sudo_command_in_terminal(cmd).await
}
