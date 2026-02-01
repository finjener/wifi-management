mod backend;
mod models;
mod ui;

use iced::widget::{column, container, row, text};
use iced::{Element, Length, Task};
use iced::clipboard;
use std::path::PathBuf;

use backend::{nmconnection, script};
use models::network::Network;
use ui::{network_list, output_panel, toolbar, add_network_dialog};

pub fn main() -> iced::Result {
    iced::application("WiFi Manager", WifiManager::update, WifiManager::view)
        .theme(|_| iced::Theme::Dark)
        .window_size(iced::Size::new(1100.0, 650.0))
        .run_with(WifiManager::new)
}

#[derive(Debug, Clone)]
pub enum Message {
    // Toolbar actions
    Toolbar(toolbar::ToolbarMessage),
    // Output panel actions
    Output(output_panel::OutputMessage),
    // Network list actions
    NetworkList(network_list::NetworkListMessage),
    // Add network dialog
    AddNetwork(add_network_dialog::AddNetworkMessage),
    // Async results
    CommandComplete(String),
    NetworksLoaded(Vec<Network>),
    SyncStatusChecked(bool, usize),
    NetworkCreated(Result<(), String>),
    // Refresh
    Refresh,
}

struct WifiManager {
    networks: Vec<Network>,
    terminal_output: String,
    is_synced: bool,
    network_count: usize,
    is_loading: bool,
    data_dir: PathBuf,
    // New state
    search_query: String,
    show_passwords: Vec<bool>,
    add_network_state: add_network_dialog::AddNetworkState,
}

impl WifiManager {
    fn new() -> (Self, Task<Message>) {
        let data_dir = get_data_dir();
        
        (
            WifiManager {
                networks: Vec::new(),
                terminal_output: String::new(),
                is_synced: false,
                network_count: 0,
                is_loading: true,
                data_dir: data_dir.clone(),
                search_query: String::new(),
                show_passwords: Vec::new(),
                add_network_state: add_network_dialog::AddNetworkState::new(),
            },
            Task::perform(
                async move { load_initial_data(data_dir).await },
                |(networks, _, _)| Message::NetworksLoaded(networks),
            ),
        )
    }

    fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::Toolbar(toolbar_msg) => {
                self.is_loading = true;
                let cmd = match toolbar_msg {
                    toolbar::ToolbarMessage::ImportXml => "import-android",
                    toolbar::ToolbarMessage::Install => "install",
                    toolbar::ToolbarMessage::Backup => "backup",
                    toolbar::ToolbarMessage::Sync => "sync-local",
                    toolbar::ToolbarMessage::PullAdb => "pull-android",
                    toolbar::ToolbarMessage::PushAdb => "push-android",
                };
                
                let needs_sudo = matches!(
                    toolbar_msg,
                    toolbar::ToolbarMessage::Install | toolbar::ToolbarMessage::Backup
                );
                
                Task::perform(
                    async move {
                        let result = if needs_sudo {
                            script::run_sudo_command_in_terminal(cmd).await
                        } else {
                            script::run_command_in_terminal(cmd).await
                        };
                        
                        match result {
                            Ok(output) => {
                                if output.success {
                                    output.stdout
                                } else {
                                    format!("{}\\n{}", output.stdout, output.stderr)
                                }
                            }
                            Err(e) => e,
                        }
                    },
                    Message::CommandComplete,
                )
            }
            
            Message::Output(output_msg) => {
                match output_msg {
                    output_panel::OutputMessage::Copy => {
                        return clipboard::write(self.terminal_output.clone());
                    }
                    output_panel::OutputMessage::Clear => {
                        self.terminal_output.clear();
                    }
                }
                Task::none()
            }
            
            Message::NetworkList(list_msg) => {
                match list_msg {
                    network_list::NetworkListMessage::SearchChanged(query) => {
                        self.search_query = query;
                    }
                    network_list::NetworkListMessage::AddNetwork => {
                        self.add_network_state.show();
                    }
                    network_list::NetworkListMessage::TogglePassword(idx) => {
                        // Resize if needed
                        while self.show_passwords.len() <= idx {
                            self.show_passwords.push(false);
                        }
                        self.show_passwords[idx] = !self.show_passwords[idx];
                    }
                }
                Task::none()
            }
            
            Message::AddNetwork(dialog_msg) => {
                match dialog_msg {
                    add_network_dialog::AddNetworkMessage::SsidChanged(s) => {
                        self.add_network_state.ssid = s;
                    }
                    add_network_dialog::AddNetworkMessage::PasswordChanged(p) => {
                        self.add_network_state.password = p;
                    }
                    add_network_dialog::AddNetworkMessage::SecurityChanged(sec) => {
                        self.add_network_state.security = sec;
                    }
                    add_network_dialog::AddNetworkMessage::Cancel => {
                        self.add_network_state.hide();
                    }
                    add_network_dialog::AddNetworkMessage::Submit => {
                        let data_dir = self.data_dir.clone();
                        let ssid = self.add_network_state.ssid.clone();
                        let password = self.add_network_state.password.clone();
                        let security = self.add_network_state.security.clone();
                        
                        self.add_network_state.hide();
                        self.is_loading = true;
                        
                        return Task::perform(
                            async move {
                                nmconnection::create_network(&data_dir, &ssid, &password, &security)
                            },
                            Message::NetworkCreated,
                        );
                    }
                }
                Task::none()
            }
            
            Message::NetworkCreated(result) => {
                match result {
                    Ok(()) => {
                        self.terminal_output.push_str("[INFO] Network created successfully\n");
                        // Trigger sync
                        self.is_loading = true;
                        return Task::perform(
                            async move {
                                script::run_command("sync-local").await
                            },
                            |result| {
                                Message::CommandComplete(
                                    result.map(|o| o.stdout).unwrap_or_else(|e| e)
                                )
                            },
                        );
                    }
                    Err(e) => {
                        self.terminal_output.push_str(&format!("[ERROR] {}\n", e));
                        self.is_loading = false;
                    }
                }
                Task::none()
            }
            
            Message::CommandComplete(output) => {
                self.terminal_output.push_str(&output);
                self.terminal_output.push('\n');
                self.is_loading = false;
                
                // Refresh networks after command
                let data_dir = self.data_dir.clone();
                Task::perform(
                    async move {
                        let networks = nmconnection::load_networks(&data_dir.join("network_connections"));
                        let (is_synced, count) = nmconnection::check_sync_status(&data_dir);
                        (networks, is_synced, count)
                    },
                    |(networks, _, _)| Message::NetworksLoaded(networks),
                )
            }
            
            Message::NetworksLoaded(networks) => {
                self.show_passwords = vec![false; networks.len()];
                self.networks = networks;
                self.is_loading = false;
                
                let data_dir = self.data_dir.clone();
                Task::perform(
                    async move {
                        nmconnection::check_sync_status(&data_dir)
                    },
                    |(is_synced, count)| Message::SyncStatusChecked(is_synced, count),
                )
            }
            
            Message::SyncStatusChecked(is_synced, count) => {
                self.is_synced = is_synced;
                self.network_count = count;
                Task::none()
            }
            
            Message::Refresh => {
                let data_dir = self.data_dir.clone();
                Task::perform(
                    async move {
                        nmconnection::load_networks(&data_dir.join("network_connections"))
                    },
                    Message::NetworksLoaded,
                )
            }
        }
    }

    fn view(&self) -> Element<'_, Message> {
        // Status bar with loading indicator
        let status_text = if self.is_loading {
            "⏳ Loading...".to_string()
        } else if self.is_synced {
            format!("✓ Synced ({} networks)", self.network_count)
        } else {
            format!("⚠ Not synced ({} networks)", self.network_count)
        };
        let status_bar = container(text(status_text).size(14))
            .padding(10)
            .width(Length::Fill);
        
        // Toolbar (disabled during loading)
        let toolbar = toolbar::view(self.is_loading).map(Message::Toolbar);
        
        // Main content: network list (left) | output panel (right)
        let network_list: Element<Message> = network_list::view(
            &self.networks, 
            &self.search_query,
            &self.show_passwords,
        ).map(Message::NetworkList);
        
        let output_panel = output_panel::view(&self.terminal_output).map(Message::Output);
        
        // Add network dialog (overlay)
        let add_dialog = add_network_dialog::view(&self.add_network_state).map(Message::AddNetwork);
        
        let main_content = row![
            container(column![network_list, add_dialog])
                .width(Length::FillPortion(2))
                .height(Length::Fill)
                .padding(10),
            container(output_panel)
                .width(Length::FillPortion(3))
                .height(Length::Fill)
                .padding(10),
        ]
        .spacing(10);
        
        // Full layout
        column![
            status_bar,
            toolbar,
            main_content,
        ]
        .spacing(5)
        .into()
    }
}

fn get_data_dir() -> PathBuf {
    // Try to find data directory relative to executable
    if let Ok(exe_path) = std::env::current_exe() {
        let mut path = exe_path;
        path.pop(); // binary
        path.pop(); // release/debug
        path.pop(); // target
        path.push("data");
        if path.exists() {
            return path;
        }
    }
    
    // Fallback to current directory
    PathBuf::from("../data")
}

async fn load_initial_data(data_dir: PathBuf) -> (Vec<Network>, bool, usize) {
    let networks = nmconnection::load_networks(&data_dir.join("network_connections"));
    let (is_synced, count) = nmconnection::check_sync_status(&data_dir);
    (networks, is_synced, count)
}
