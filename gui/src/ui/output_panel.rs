use iced::widget::{button, column, container, row, scrollable, text};
use iced::{Border, Color, Element, Length, Theme};

#[derive(Debug, Clone)]
pub enum OutputMessage {
    Copy,
    Clear,
}

pub fn view<'a>(output: &'a str) -> Element<'a, OutputMessage> {
    let buttons = row![
        button("📋 Copy").on_press(OutputMessage::Copy),
        button("🗑 Clear").on_press(OutputMessage::Clear),
    ]
    .spacing(10);
    
    // Terminal-like styling
    let terminal_content = container(
        scrollable(
            text(if output.is_empty() { "Terminal output will appear here..." } else { output })
                .size(13)
                .font(iced::Font::MONOSPACE)
        )
        .height(Length::Fill)
    )
    .width(Length::Fill)
    .height(Length::Fill)
    .padding(10)
    .style(|_theme: &Theme| {
        container::Style {
            background: Some(Color::from_rgb(0.1, 0.1, 0.12).into()),
            border: Border {
                color: Color::from_rgb(0.3, 0.3, 0.35),
                width: 1.0,
                radius: 4.0.into(),
            },
            ..Default::default()
        }
    });
    
    column![
        row![
            text("Terminal Output").size(14),
            buttons
        ]
        .spacing(20)
        .align_y(iced::Alignment::Center),
        terminal_content,
    ]
    .spacing(8)
    .width(Length::Fill)
    .height(Length::Fill)
    .into()
}
