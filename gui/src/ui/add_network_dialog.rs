use iced::widget::{button, column, container, row, text, text_input, pick_list};
use iced::{Element, Length};

#[derive(Debug, Clone)]
pub enum AddNetworkMessage {
    SsidChanged(String),
    PasswordChanged(String),
    SecurityChanged(String),
    Submit,
    Cancel,
}

#[derive(Debug, Clone, Default)]
pub struct AddNetworkState {
    pub ssid: String,
    pub password: String,
    pub security: String,
    pub visible: bool,
}

impl AddNetworkState {
    pub fn new() -> Self {
        Self {
            ssid: String::new(),
            password: String::new(),
            security: "WPA/WPA2".to_string(),
            visible: false,
        }
    }
    
    pub fn show(&mut self) {
        self.visible = true;
        self.ssid.clear();
        self.password.clear();
        self.security = "WPA/WPA2".to_string();
    }
    
    pub fn hide(&mut self) {
        self.visible = false;
    }
}

const SECURITY_OPTIONS: &[&str] = &["WPA/WPA2", "WPA3", "Open"];

pub fn view<'a>(state: &'a AddNetworkState) -> Element<'a, AddNetworkMessage> {
    if !state.visible {
        return container(column![]).into();
    }
    
    let content = column![
        text("Add New Network").size(18),
        text("SSID:").size(14),
        text_input("Network name", &state.ssid)
            .on_input(AddNetworkMessage::SsidChanged)
            .padding(8),
        text("Password:").size(14),
        text_input("Password (leave empty for Open)", &state.password)
            .on_input(AddNetworkMessage::PasswordChanged)
            .padding(8)
            .secure(true),
        text("Security:").size(14),
        pick_list(
            SECURITY_OPTIONS.to_vec(),
            Some(state.security.as_str()),
            |s| AddNetworkMessage::SecurityChanged(s.to_string()),
        ),
        row![
            button("Cancel").on_press(AddNetworkMessage::Cancel),
            button("Add Network").on_press(AddNetworkMessage::Submit),
        ].spacing(10),
    ]
    .spacing(10)
    .padding(20)
    .width(Length::Fixed(350.0));
    
    container(content)
        .padding(10)
        .into()
}
