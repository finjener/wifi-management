use std::fs;
use std::path::Path;
use crate::models::network::Network;
use uuid::Uuid;

/// Parse a single .nmconnection file
pub fn parse_file(path: &Path) -> Option<Network> {
    let content = fs::read_to_string(path).ok()?;
    
    let mut ssid = String::new();
    let mut security = String::from("Unknown");
    let mut password = None;
    let mut section = String::new();
    
    for line in content.lines() {
        let line = line.trim();
        
        if line.starts_with('[') && line.ends_with(']') {
            section = line[1..line.len()-1].to_string();
            continue;
        }
        
        if let Some((key, value)) = line.split_once('=') {
            match (section.as_str(), key) {
                ("wifi", "ssid") => ssid = value.to_string(),
                ("connection", "id") if ssid.is_empty() => ssid = value.to_string(),
                ("wifi-security", "key-mgmt") => {
                    security = match value {
                        v if v.contains("wpa") => "WPA/WPA2".to_string(),
                        v if v.contains("sae") => "WPA3".to_string(),
                        _ => "Unknown".to_string(),
                    };
                }
                ("wifi-security", "psk") => password = Some(value.to_string()),
                _ => {}
            }
        }
    }
    
    if ssid.is_empty() {
        return None;
    }
    
    // If no security section but no password, it's open
    if password.is_none() && security == "Unknown" {
        security = "Open".to_string();
    }
    
    Some(Network::new(ssid, security, password))
}

/// Load all networks from a directory
pub fn load_networks(dir: &Path) -> Vec<Network> {
    let mut networks = Vec::new();
    
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map_or(false, |e| e == "nmconnection") {
                if let Some(network) = parse_file(&path) {
                    networks.push(network);
                }
            }
        }
    }
    
    networks.sort_by(|a, b| a.ssid.to_lowercase().cmp(&b.ssid.to_lowercase()));
    networks
}

/// Check if report and nmconnection files are in sync
pub fn check_sync_status(data_dir: &Path) -> (bool, usize) {
    let connections_dir = data_dir.join("network_connections");
    let report_file = data_dir.join("networks_report.md");
    
    let nmconnection_count = fs::read_dir(&connections_dir)
        .map(|entries| {
            entries
                .flatten()
                .filter(|e| e.path().extension().map_or(false, |ext| ext == "nmconnection"))
                .count()
        })
        .unwrap_or(0);
    
    // Simple sync check: report exists and has same network count
    let report_count = if report_file.exists() {
        fs::read_to_string(&report_file)
            .map(|content| {
                content.lines()
                    .filter(|line| line.starts_with('|') && !line.contains("Network Name") && !line.contains("---"))
                    .count()
            })
            .unwrap_or(0)
    } else {
        0
    };
    
    (nmconnection_count == report_count && nmconnection_count > 0, nmconnection_count)
}

/// Create a new .nmconnection file
pub fn create_network(data_dir: &Path, ssid: &str, password: &str, security: &str) -> Result<(), String> {
    let connections_dir = data_dir.join("network_connections");
    
    // Create directory if it doesn't exist
    fs::create_dir_all(&connections_dir)
        .map_err(|e| format!("Failed to create directory: {}", e))?;
    
    // Sanitize filename
    let safe_name: String = ssid.chars()
        .map(|c| if "<>:\"/\\|?*".contains(c) { '_' } else { c })
        .collect();
    
    let filepath = connections_dir.join(format!("{}.nmconnection", safe_name));
    
    let uuid = Uuid::new_v4();
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_micros();
    
    let mut content = format!(
        r#"[connection]
id={ssid}
uuid={uuid}
type=wifi
autoconnect=true
timestamp={timestamp}

[wifi]
mode=infrastructure
ssid={ssid}
hidden=false

"#
    );
    
    // Add security section if password provided
    if !password.is_empty() && security != "Open" {
        let key_mgmt = match security {
            "WPA3" => "sae",
            _ => "wpa-psk",
        };
        content.push_str(&format!(
            r#"[wifi-security]
auth-alg=open
key-mgmt={key_mgmt}
psk={password}

"#
        ));
    }
    
    content.push_str(
        r#"[ipv4]
method=auto
dns-search=

[ipv6]
addr-gen-mode=stable-privacy
method=auto
dns-search=

[proxy]
"#
    );
    
    fs::write(&filepath, content)
        .map_err(|e| format!("Failed to write file: {}", e))?;
    
    Ok(())
}
