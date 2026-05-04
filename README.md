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

## GPIO Peripherals

### Piezo Buzzer (KY-006 passive)

Provides audible feedback when a USB backup drive is inserted and when the backup completes.

| KY-006 pin | Pi header pin | Notes |
|---|---|---|
| VCC | Pin 1 (3.3V) | |
| GND | Pin 9 (GND) | |
| IO (signal) | Pin 11 (GPIO 17) | |

Driven by `bin/buzzer.py` (uses `RPi.GPIO`, pre-installed on Pi OS). No additional packages required.

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

## Deploying via USB Drive

Place `ERC-Update.bundle` in the root of the ERCBACKUP drive alongside a valid `user.txt`.
When the drive is inserted the system runs a full backup first (restore point), then applies
the update, and deletes the bundle from the drive on success. A failed deploy auto-rolls back
the git tree and restarts the service.

**Create the bundle on your dev machine:**

```bash
# Bundle all commits on the current branch not yet on the Pi's main
git bundle create ERC-Update.bundle origin/main..HEAD
# Copy ERC-Update.bundle to the ERCBACKUP drive root
```

**What the Pi does automatically:**
1. Full backup (controller log + CSVs + SQLite)
2. `git fetch` + `git merge` the bundle
3. `bundle install`
4. `db:migrate`
5. `assets:precompile`
6. Restart the `iei` service
7. Delete `ERC-Update.bundle` from the drive
8. Log an *App Updated* event (or *Update Failed* on rollback)

**Rollback note:** if any step fails, the git tree is reset to the pre-update commit and the
service is restarted. If `db:migrate` ran partially before failing, the schema may be ahead
of the rolled-back code — check `/var/log/iei-backup.log` and recover with a corrected bundle.

---

## Deploying Updates (via SSH / network)

```bash
# On your dev machine
git push origin main

# On the Pi
cd /opt/iei
git pull
bundle install                                       # only if Gemfile.lock changed — no flags needed
RAILS_ENV=production bin/rails db:migrate           # only if there are new migrations
RAILS_ENV=production bin/rails assets:precompile    # only if CSS/JS changed
sudo systemctl restart iei
```

---

## Admin Authentication

The web UI is protected by a single admin password stored as a bcrypt digest in `config/credentials.yml.enc`. The master key (`config/master.key`) is never committed to git — keep it safe.

### Changing the password

On your dev machine:

```bash
# 1. Generate a new bcrypt digest
bin/rails runner 'puts BCrypt::Password.create("yournewpassword")'

# 2. Store it in credentials
bin/rails credentials:edit
```

Add or update:

```yaml
admin_password_digest: <paste digest here>
```

Then deploy normally (`git push` → `git pull` on Pi → `sudo systemctl restart iei`).

---

## Useful Commands

| Task | Command |
|---|---|
| View logs | `sudo journalctl -u iei -f` |
| Restart app | `sudo systemctl restart iei` |
| Rails console | `cd /opt/iei && RAILS_ENV=production bin/rails console` |
| DB console | `cd /opt/iei && RAILS_ENV=production bin/rails dbconsole` |
