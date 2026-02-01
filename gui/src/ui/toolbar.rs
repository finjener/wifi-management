use iced::widget::{button, column, row, text};
use iced::{Alignment, Element};

#[derive(Debug, Clone)]
pub enum ToolbarMessage {
    ImportXml,
    Install,
    Backup,
    Sync,
    PullAdb,
    PushAdb,
}

pub fn view<'a>(is_loading: bool) -> Element<'a, ToolbarMessage> {
    // Multi-line button for Sync
    let sync_button = button(
        column![
            text("Sync").size(14),
            text("Report-Local").size(10),
        ]
        .align_x(Alignment::Center)
    );
    
    let sync_button = if is_loading {
        sync_button
    } else {
        sync_button.on_press(ToolbarMessage::Sync)
    };

    // Disable buttons when loading
    let import_btn = if is_loading { button("Import XML") } else { button("Import XML").on_press(ToolbarMessage::ImportXml) };
    let install_btn = if is_loading { button("Install") } else { button("Install").on_press(ToolbarMessage::Install) };
    let backup_btn = if is_loading { button("Backup") } else { button("Backup").on_press(ToolbarMessage::Backup) };
    let pull_btn = if is_loading { button("Pull ADB") } else { button("Pull ADB").on_press(ToolbarMessage::PullAdb) };
    let push_btn = if is_loading { button("Push ADB") } else { button("Push ADB").on_press(ToolbarMessage::PushAdb) };

    row![
        import_btn,
        install_btn,
        backup_btn,
        sync_button,
        pull_btn,
        push_btn,
    ]
    .spacing(10)
    .padding(10)
    .into()
}
