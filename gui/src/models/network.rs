use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Network {
    pub ssid: String,
    pub security: String,
    pub password: Option<String>,
}

impl Network {
    pub fn new(ssid: String, security: String, password: Option<String>) -> Self {
        Self { ssid, security, password }
    }

    pub fn password_display(&self) -> String {
        match &self.password {
            Some(p) if !p.is_empty() => "••••••••".to_string(),
            _ => "N/A".to_string(),
        }
    }
}
