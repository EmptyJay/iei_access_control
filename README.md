# IEI Access Control

Rails 8 app for managing member access via an IEI Max3 v2 door controller over RS-485 serial.

- **Hardware:** IEI Max3 v2 controller, RS-485 to USB adapter
- **Platform:** Raspberry Pi (aarch64, Debian Trixie)
- **Ruby:** 3.2.3
- **Database:** SQLite3
- **Serial port:** `/dev/ttyUSB0` (override with `MAX3_PORT` env var)

---

## Raspberry Pi Setup

### 1. OS

Raspberry Pi OS 64-bit (Bookworm or later). Verify with:

```bash
uname -a   # should show aarch64
```

### 2. System Dependencies

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential libssl-dev libreadline-dev zlib1g-dev \
  libsqlite3-dev sqlite3 libyaml-dev
```

### 3. Ruby

Ruby 3.2.3 must be installed. If not present, install via rbenv:

```bash
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc
rbenv install 3.2.3
rbenv global 3.2.3
gem install bundler
```

### 4. Serial Port Access

Add your user to the `dialout` group:

```bash
sudo usermod -aG dialout $USER
```

Log out and back in for this to take effect. Verify with `groups`.

### 5. GitHub SSH Deploy Key

Generate a key on the Pi:

```bash
ssh-keygen -t ed25519 -C "iei-pi" -f ~/.ssh/github_deploy
```

Add to SSH config:

```bash
cat >> ~/.ssh/config << 'EOF'

Host github.com
  IdentityFile ~/.ssh/github_deploy
EOF
```

Copy the public key and add it to the GitHub repo under **Settings → Deploy keys**:

```bash
cat ~/.ssh/github_deploy.pub
```

Test access:

```bash
ssh -T git@github.com
```

### 6. Clone the Repo

```bash
sudo mkdir /opt/iei && sudo chown $USER:$USER /opt/iei
git clone git@github.com:EmptyJay/iei_access_control.git /opt/iei
cd /opt/iei
```

### 7. Install Gems

```bash
bundle install
```

### 8. Master Key

The file `config/master.key` is not stored in git. Copy it manually from a trusted source:

```bash
scp user@source:/path/to/master.key /opt/iei/config/master.key
```

### 9. Database Setup

```bash
cd /opt/iei
RAILS_ENV=production bin/rails db:prepare
```

### 10. Systemd Service

Create `/etc/systemd/system/iei.service`:

```ini
[Unit]
Description=IEI Access Control
After=network.target

[Service]
Type=simple
User=ercadmin
WorkingDirectory=/opt/iei
Environment=RAILS_ENV=production
Environment=MAX3_PORT=/dev/ttyUSB0
ExecStart=/home/ercadmin/.rbenv/shims/bundle exec rails server -p 3000 -b 0.0.0.0
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

> Replace `ercadmin` with your actual username. Verify the bundle path with `which bundle`.

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable iei
sudo systemctl start iei
sudo systemctl status iei
```

Verify the app is running:

```bash
curl http://localhost:3000/up
```

Should return a green HTML page.

---

## Seeding Members

Export member data from Hub Manager, then on the Pi:

```bash
RAILS_ENV=production HUB_EXPORT=/path/to/export.txt bin/rails db:seed
```

---

## Verifying Serial Comms

With the RS-485 adapter plugged in:

```bash
MAX3_PORT=/dev/ttyUSB0 RAILS_ENV=production bin/rake max3:status
```

---

## Deploying Updates

```bash
# On your dev machine
git push origin main

# On the Pi
cd /opt/iei
git pull
bundle install   # only if Gemfile.lock changed
RAILS_ENV=production bin/rails db:migrate   # only if there are new migrations
sudo systemctl restart iei
```

---

## Useful Commands

| Task | Command |
|---|---|
| View logs | `sudo journalctl -u iei -f` |
| Restart app | `sudo systemctl restart iei` |
| Rails console | `cd /opt/iei && RAILS_ENV=production bin/rails console` |
| DB console | `cd /opt/iei && RAILS_ENV=production bin/rails dbconsole` |
