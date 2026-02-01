use iced::widget::{button, column, container, row, scrollable, text, text_input, Column};
use iced::{Element, Length};
use crate::models::network::Network;

#[derive(Debug, Clone)]
pub enum NetworkListMessage {
    SearchChanged(String),
    AddNetwork,
    TogglePassword(usize),
}

pub fn view<'a>(
    networks: &'a [Network], 
    search_query: &'a str,
    show_passwords: &'a [bool],
) -> Element<'a, NetworkListMessage> {
    // Search box
    let search_box = text_input("Search networks...", search_query)
        .on_input(NetworkListMessage::SearchChanged)
        .padding(8)
        .width(Length::Fill);
    
    // Add Network button
    let add_btn = button("+ Add Network")
        .on_press(NetworkListMessage::AddNetwork)
        .padding(8);
    
    let header = row![
        text("SSID").width(Length::FillPortion(3)),
        text("Security").width(Length::FillPortion(2)),
        text("Password").width(Length::FillPortion(3)),
    ]
    .spacing(10)
    .padding(5);
    
    // Filter networks by search query
    let filtered: Vec<(usize, &Network)> = networks
        .iter()
        .enumerate()
        .filter(|(_, n)| {
            if search_query.is_empty() {
                true
            } else {
                n.ssid.to_lowercase().contains(&search_query.to_lowercase())
            }
        })
        .collect();
    
    let rows: Vec<Element<'a, NetworkListMessage>> = filtered
        .iter()
        .map(|(idx, network)| {
            let show_pass = show_passwords.get(*idx).copied().unwrap_or(false);
            let pass_text: String = if show_pass {
                network.password.clone().unwrap_or_else(|| "N/A".to_string())
            } else {
                if network.password.is_some() {
                    "••••••••".to_string()
                } else {
                    "N/A".to_string()
                }
            };
            
            // Clone values to avoid lifetime issues
            let ssid = network.ssid.clone();
            let security = network.security.clone();
            let idx_copy = *idx;
            
            row![
                text(ssid).width(Length::FillPortion(3)).size(13),
                text(security).width(Length::FillPortion(2)).size(13),
                button(text(pass_text).size(12))
                    .on_press(NetworkListMessage::TogglePassword(idx_copy))
                    .padding(2)
                    .width(Length::FillPortion(3)),
            ]
            .spacing(10)
            .padding(4)
            .into()
        })
        .collect();
    
    let list = Column::with_children(rows).spacing(2);
    let count_text = text(format!("Showing {} of {} networks", filtered.len(), networks.len())).size(12);
    
    column![
        row![search_box, add_btn].spacing(10),
        count_text,
        header,
        container(text("─".repeat(60))).padding(2),
        scrollable(list).height(Length::Fill),
    ]
    .spacing(5)
    .into()
}
