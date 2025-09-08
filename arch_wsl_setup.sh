#!/bin/bash

# Arch Linux WSL Post-Installation Setup Script
# This script automates the setup process described in the markdown file

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log "Running as root - this is expected for initial setup"
        return 0
    else
        error "This script should be run as root initially"
        exit 1
    fi
}

# Update system and install sudo
update_and_install_basics() {
    log "Updating system and installing basic packages..."
    pacman -Syu --noconfirm
    pacman -S --noconfirm sudo zsh
}

# Create sudo user
create_user() {
    local username="alex"
    
    log "Creating user: $username"
    
    # Create user with home directory and zsh as default shell
    useradd -m -s /bin/zsh "$username" 2>/dev/null || {
        warning "User $username already exists, skipping creation"
        return 0
    }
    
    # Set password for user
    log "Please set password for user $username:"
    passwd "$username"
    
    # Add user to wheel group
    usermod -aG wheel "$username"
    
    # Enable wheel group for sudo
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    
    # Set default user in WSL config
    log "Setting $username as default WSL user..."
    echo -e "[user]\ndefault=$username" | tee -a /etc/wsl.conf > /dev/null
    
    # Copy this script to the user's home directory for Phase 2
    log "Copying setup script to /home/$username/ for Phase 2..."
    cp "$0" "/home/$username/arch_wsl_setup.sh"
    chmod +x "/home/$username/arch_wsl_setup.sh"
    chown "$username:$username" "/home/$username/arch_wsl_setup.sh"
    
    log "User setup complete. Please exit WSL and run 'wsl --shutdown', then restart with 'wsl -d archlinux'"
    log "After restart, run: ./arch_wsl_setup.sh (the script is now in your home directory)"
}

# Check if we're running as the alex user
check_user_context() {
    if [[ $(whoami) != "alex" ]]; then
        error "This part of the setup should be run as user 'alex'"
        info "Please exit WSL, run 'wsl --shutdown', restart with 'wsl -d archlinux', and run this script again"
        exit 1
    fi
}

# Setup zsh configuration
setup_zsh() {
    log "Setting up zsh configuration..."
    
    # Create .zshrc if prompted (this handles the zsh first-run prompt)
    if [[ ! -f ~/.zshrc ]]; then
        echo "# Initial zsh configuration" > ~/.zshrc
    fi
    
    # Fix locale
    log "Fixing locale settings..."
    sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen
    echo -e 'export LANG=en_US.UTF-8\nexport LC_ALL=en_US.UTF-8' >> ~/.zshrc
    source ~/.zshrc
}

# Install git and build dependencies
install_build_tools() {
    log "Installing git and build dependencies..."
    sudo pacman -S --needed --noconfirm git base-devel
}

# Install yay AUR helper
install_yay() {
    log "Installing yay AUR helper..."
    
    if command -v yay &> /dev/null; then
        warning "yay already installed, skipping"
        return 0
    fi
    
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
}

# Install packages from official repos
install_packages() {
    log "Installing packages from official repositories..."
    
    local packages=(
        "alacritty"
        "lazygit"
        "neovim"
        "yazi"
        "fzf"
        "bat"
        "github-cli"
        "zoxide"
        "vim"
        "stow"
        "tmux"
        "zsh-autosuggestions"
        "zsh-syntax-highlighting"
    )
    
    sudo pacman -Syu --needed --noconfirm "${packages[@]}"
}

# Install Homebrew
install_homebrew() {
    log "Installing Homebrew..."
    
    if command -v brew &> /dev/null; then
        warning "Homebrew already installed, skipping"
        return 0
    fi
    
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

# Install Oh My Zsh
install_oh_my_zsh() {
    log "Installing Oh My Zsh..."
    
    if [[ -d ~/.oh-my-zsh ]]; then
        warning "Oh My Zsh already installed, skipping"
        return 0
    fi
    
    # Backup current .zshrc
    if [[ -f ~/.zshrc ]]; then
        cp ~/.zshrc ~/.zshrc.backup
    fi
    
    # Install Oh My Zsh and prevent it from overwriting .zshrc
    export KEEP_ZSHRC=yes
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    
    # Restore our .zshrc if it was backed up
    if [[ -f ~/.zshrc.backup ]]; then
        mv ~/.zshrc.backup ~/.zshrc
    fi
}

# Install Powerlevel10k theme
install_powerlevel10k() {
    log "Installing Powerlevel10k theme..."
    
    local theme_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    
    if [[ -d "$theme_dir" ]]; then
        warning "Powerlevel10k already installed, skipping"
        return 0
    fi
    
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"
}

# Configure zsh plugins and settings
configure_zsh() {
    log "Configuring zsh plugins and settings..."
    
    # Create Oh My Zsh custom plugins directory
    local omz_plugins_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
    mkdir -p "$omz_plugins_dir"
    
    # Create symlinks for system-installed plugins in Oh My Zsh directory
    ln -sf /usr/share/zsh/plugins/zsh-autosuggestions "$omz_plugins_dir/zsh-autosuggestions" 2>/dev/null || true
    ln -sf /usr/share/zsh/plugins/zsh-syntax-highlighting "$omz_plugins_dir/zsh-syntax-highlighting" 2>/dev/null || true
    
    # Add cd command to start in home directory
    if ! grep -q "cd /home/alex" ~/.zshrc; then
        sed -i '1i cd /home/alex' ~/.zshrc
    fi
    
    # Add Powerlevel10k quiet setting
    if ! grep -q "POWERLEVEL9K_INSTANT_PROMPT=quiet" ~/.zshrc; then
        echo 'typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet' >> ~/.zshrc
    fi
    
    # Configure Oh My Zsh to use Powerlevel10k theme and our plugins
    if ! grep -q "ZSH_THEME=\"powerlevel10k/powerlevel10k\"" ~/.zshrc; then
        echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> ~/.zshrc
    fi
    
    if ! grep -q "plugins=(git zsh-autosuggestions zsh-syntax-highlighting)" ~/.zshrc; then
        echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> ~/.zshrc
    fi
}

# Install safe-rm from AUR
install_safe_rm() {
    log "Installing safe-rm from AUR..."
    
    if command -v safe-rm &> /dev/null; then
        warning "safe-rm already installed, skipping"
        return 0
    fi
    
    # Install safe-rm, automatically choosing rust as cargo provider and accepting defaults
    echo -e "1\n\n" | yay -S --needed --noconfirm safe-rm
}

# Setup dotfiles (requires manual GitHub authentication)
setup_dotfiles() {
    log "Setting up dotfiles..."
    
    info "You need to authenticate with GitHub first."
    info "Please run: gh auth login"
    info "Then go to github.com/login/device and enter the one-time code"
    
    read -p "Press Enter after you've completed GitHub authentication..."
    
    # Check if already authenticated
    if ! gh auth status &> /dev/null; then
        error "GitHub authentication not completed. Please run 'gh auth login' manually"
        return 1
    fi
    
    # Clone dotfiles repo
    cd ~
    if [[ ! -d ~/.dotfiles ]]; then
        gh repo clone alex-assada/hypr-dots
        mv hypr-dots .dotfiles
    else
        warning "Dotfiles directory already exists, skipping clone"
    fi
    
    # Use stow to symlink config files
    cd ~/.dotfiles
    
    # Remove existing .zshrc to avoid conflicts
    if [[ -f ~/.zshrc ]]; then
        rm ~/.zshrc
    fi
    
    # Stow the configuration files
    stow alacritty nvim tmux yazi zsh
    
    log "Dotfiles setup complete!"
}

# Main execution
main() {
    log "Starting Arch Linux WSL post-installation setup..."
    
    # Check if we're in the initial root setup phase
    if [[ $EUID -eq 0 ]]; then
        log "Phase 1: Root setup"
        update_and_install_basics
        create_user
        return 0
    fi
    
    # Phase 2: User setup
    log "Phase 2: User setup"
    check_user_context
    
    setup_zsh
    install_build_tools
    install_yay
    install_packages
    install_homebrew
    install_oh_my_zsh
    install_powerlevel10k
    configure_zsh
    install_safe_rm
    
    log "Most setup complete!"
    log "Configuration complete! Sourcing .zshrc to activate Oh My Zsh and Powerlevel10k..."
    
    # Source .zshrc to trigger Powerlevel10k configuration wizard
    info "You may be prompted to configure the Powerlevel10k theme now."
    source ~/.zshrc
    
    log "Next steps:"
    info "1. If you didn't see the Powerlevel10k configuration wizard, run: p10k configure"
    info "2. For dotfiles setup, you'll need to manually authenticate with GitHub:"
    info "   - Run: gh auth login"
    info "   - Follow the prompts and device authentication"
    info "   - Then run the dotfiles section manually or re-run this script"
    
    read -p "Would you like to set up dotfiles now? (y/N): " setup_dots
    if [[ $setup_dots =~ ^[Yy]$ ]]; then
        setup_dotfiles
    fi
    
    log "Setup complete! Enjoy your new Arch Linux WSL environment!"
}

# Run main function
main "$@"
