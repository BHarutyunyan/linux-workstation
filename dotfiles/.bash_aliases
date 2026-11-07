# ~/.bash_aliases: my own shortcuts. Ubuntu's ~/.bashrc loads this file.

# system
alias update='sudo apt update && sudo apt upgrade -y'
alias ports='sudo ss -tulnp'            # who listens on which port
alias fw='sudo ufw status verbose'      # firewall rules
alias myip='ip -br addr'                # my addresses, short form

# git
alias gs='git status'
alias gl='git log --oneline -10'

# my services
alias n8n-logs='sudo docker logs --tail 50 n8n'
alias models='ollama list'
