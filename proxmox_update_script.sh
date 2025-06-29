#!/bin/bash

# Proxmox System Update and Metrics Script
# For Debian 12 based Proxmox systems

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root or with sudo
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        print_status "Running as root"
        SUDO_CMD=""
    elif command -v sudo >/dev/null 2>&1; then
        print_status "Sudo is available"
        SUDO_CMD="sudo"
        # Test sudo access
        if ! sudo -n true 2>/dev/null; then
            print_warning "Sudo access required. You may be prompted for password."
        fi
    else
        print_error "Neither root access nor sudo is available!"
        print_error "Please install sudo or run as root"
        exit 1
    fi
}

# Function to check if sudo is installed
check_sudo_installation() {
    print_status "Checking sudo installation..."
    
    if command -v sudo >/dev/null 2>&1; then
        print_success "Sudo is installed"
        sudo --version | head -1
    else
        print_warning "Sudo is not installed"
        print_status "Installing sudo..."
        
        if [[ $EUID -ne 0 ]]; then
            print_error "Root access required to install sudo"
            exit 1
        fi
        
        apt-get update
        apt-get install -y sudo
        print_success "Sudo installed successfully"
    fi
    echo
}

# Function to check for enterprise version and run community script
check_enterprise_and_run_community_script() {
    print_status "Checking for Proxmox Enterprise configuration..."
    
    # Check if enterprise repository is configured
    enterprise_found=false
    
    # Check for enterprise repository in sources
    if [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
        if grep -q "^deb.*enterprise.proxmox.com" /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null; then
            enterprise_found=true
            print_warning "Enterprise repository detected in pve-enterprise.list"
        fi
    fi
    
    # Also check main sources.list for enterprise entries
    if grep -q "enterprise.proxmox.com" /etc/apt/sources.list 2>/dev/null; then
        enterprise_found=true
        print_warning "Enterprise repository detected in main sources.list"
    fi
    
    # Check for PBS enterprise repository as well
    if [[ -f /etc/apt/sources.list.d/pbs-enterprise.list ]]; then
        if grep -q "^deb.*enterprise.proxmox.com" /etc/apt/sources.list.d/pbs-enterprise.list 2>/dev/null; then
            enterprise_found=true
            print_warning "PBS Enterprise repository detected"
        fi
    fi
    
    if [[ "$enterprise_found" == true ]]; then
        print_status "Enterprise version detected. Running community post-install script..."
        echo
        
        # Check if curl is installed
        if ! command -v curl >/dev/null 2>&1; then
            print_status "Installing curl..."
            $SUDO_CMD apt-get update
            $SUDO_CMD apt-get install -y curl
        fi
        
        # Download and run the community script
        print_status "Downloading and executing community post-install script..."
        print_warning "This will disable enterprise repositories and enable community repositories"
        
        # Give user a chance to cancel
        echo -n "Continue? (y/N): "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            $SUDO_CMD bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/post-pbs-install.sh)"
            print_success "Community post-install script executed successfully"
        else
            print_warning "Community script execution cancelled by user"
        fi
    else
        print_success "No enterprise repositories detected - community repositories likely already configured"
    fi
    echo
}

# Function to update system packages
update_system() {
    print_status "Starting system update process..."
    echo
    
    print_status "Updating package lists..."
    $SUDO_CMD apt-get update
    
    print_status "Upgrading packages..."
    $SUDO_CMD apt-get upgrade -y
    
    print_status "Performing distribution upgrade..."
    $SUDO_CMD apt-get dist-upgrade -y
    
    print_status "Cleaning up unnecessary packages..."
    $SUDO_CMD apt-get autoremove -y
    $SUDO_CMD apt-get autoclean
    
    print_success "System update completed successfully"
    echo
}

# Function to display system metrics
display_system_metrics() {
    print_status "Gathering system metrics..."
    echo
    
    # System information
    echo -e "${BLUE}=== SYSTEM INFORMATION ===${NC}"
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p)"
    echo "Kernel: $(uname -r)"
    echo "Distribution: $(lsb_release -d | cut -f2)"
    echo "Architecture: $(uname -m)"
    echo
    
    # CPU information
    echo -e "${BLUE}=== CPU INFORMATION ===${NC}"
    echo "CPU Model: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"
    echo "CPU Cores: $(nproc)"
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
    echo "Load Average: $(cat /proc/loadavg | cut -d' ' -f1-3)"
    echo
    
    # Memory information
    echo -e "${BLUE}=== MEMORY INFORMATION ===${NC}"
    free -h | grep -E "Mem|Swap"
    echo
    
    # Disk information
    echo -e "${BLUE}=== DISK USAGE ===${NC}"
    df -h | grep -E "^/dev|^tmpfs" | grep -v "/boot"
    echo
    
    # Network interfaces
    echo -e "${BLUE}=== NETWORK INTERFACES ===${NC}"
    ip -brief addr show | grep -v "lo"
    echo
    
    # Proxmox specific information
    echo -e "${BLUE}=== PROXMOX INFORMATION ===${NC}"
    if command -v pveversion >/dev/null 2>&1; then
        echo "Proxmox VE Version:"
        pveversion
        echo
        
        echo "Cluster Status:"
        if command -v pvecm >/dev/null 2>&1; then
            pvecm status 2>/dev/null || echo "Not part of a cluster or cluster service not running"
        else
            echo "Cluster management not available"
        fi
        echo
        
        echo "VM/Container List:"
        if command -v qm >/dev/null 2>&1; then
            qm list 2>/dev/null || echo "No VMs found or insufficient permissions"
        fi
        
        if command -v pct >/dev/null 2>&1; then
            pct list 2>/dev/null || echo "No containers found or insufficient permissions"
        fi
    else
        print_warning "Proxmox commands not found - this might not be a Proxmox system"
    fi
    echo
    
    # Service status
    echo -e "${BLUE}=== IMPORTANT SERVICES STATUS ===${NC}"
    services=("ssh" "pveproxy" "pvedaemon" "pvestatd" "pve-cluster")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "$service: ${GREEN}Active${NC}"
        else
            echo -e "$service: ${RED}Inactive${NC}"
        fi
    done
    echo
    
    # Last few system updates
    echo -e "${BLUE}=== RECENT PACKAGE UPDATES ===${NC}"
    if [[ -f /var/log/apt/history.log ]]; then
        echo "Last 5 package operations:"
        grep "Start-Date" /var/log/apt/history.log | tail -5
    else
        echo "No apt history available"
    fi
    echo
    
    # System temperature (if available)
    echo -e "${BLUE}=== SYSTEM TEMPERATURE ===${NC}"
    if command -v sensors >/dev/null 2>&1; then
        sensors 2>/dev/null | grep -E "temp|Core" || echo "No temperature sensors found"
    else
        echo "lm-sensors not installed"
    fi
    echo
}

# Function to display script completion summary
display_summary() {
    echo -e "${GREEN}=== SCRIPT EXECUTION SUMMARY ===${NC}"
    echo "✓ Sudo installation checked"
    echo "✓ Enterprise repository configuration checked"
    echo "✓ System packages updated"
    echo "✓ System metrics displayed"
    echo
    print_success "All operations completed successfully!"
    echo "System is up to date and ready for use."
}

# Main execution
main() {
    echo -e "${BLUE}Proxmox System Update and Metrics Script${NC}"
    echo "========================================"
    echo
    
    # Check privileges
    check_privileges
    
    # Check and install sudo if needed
    check_sudo_installation
    
    # Check for enterprise version and run community script if needed
    check_enterprise_and_run_community_script
    
    # Update system
    update_system
    
    # Display system metrics
    display_system_metrics
    
    # Display summary
    display_summary
}

# Run main function
main "$@"