# Implementation Progress

## Completed
- [x] Research: Ansible setup for LXC/containers (SSH-based, no special plugin needed)
- [x] Research: Password-based SSH requires sshpass; become_pass for non-root users
- [x] Research: community.general collection required for pacman module
- [x] Plan: 10-step implementation plan created
- [x] Implement: Create ansible/ansible.cfg (disable host_key_checking)
- [x] Implement: Create ansible/inventory.yml (5 hosts with SSH credentials)
- [x] Implement: Create ansible/playbook.yml (OS-aware updates)
- [x] Implement: Add update state management to backup_web.py
- [x] Implement: Add run_updates() function to Flask backend
- [x] Implement: Add /api/update-systems, /api/update-status, /api/update-stream endpoints
- [x] Implement: Rename UI to "Homelab Control" and add Update card
- [x] Implement: Add JavaScript for update functionality
- [x] Implement: Update requirements.txt with dependency notes
- [x] Test: Verify all endpoints work, buttons cross-disable correctly
- [x] Fix: Address any issues found during testing

## Files Created/Modified

### New Files
| File | Purpose |
|------|--------|
| ansible/ansible.cfg | Disable SSH host key checking |
| ansible/inventory.yml | Host list with per-host SSH credentials |
| ansible/playbook.yml | OS-aware update playbook (pacman/apt) |

### Modified Files
| File | Changes |
|------|--------|
| backup_web.py | Added update state, lock, run_updates(), 3 new API endpoints |
| templates/index.html | Renamed to Homelab Control, added Update card, JS for updates, cross-disabled buttons |
| requirements.txt | Added Ansible/sshpass dependency notes |

## Summary
Added "Update All Containers & VMs" button to web UI. Button triggers Ansible playbook that:
- Updates 5 Proxmox hosts (archnas.lan, radio.lan, paperless-ngx.lan, intel-ai.lan, torrent.lan)
- Uses pacman for Arch Linux, apt for Debian
- Live log streaming via SSE
- Progress bar tracks hosts updated (0-5)
- Buttons cross-disable (only one operation at a time)
