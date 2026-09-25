module.exports = {
  apps: [{
    name: "takhfid1",
    cwd: "/home/root/projects/takhfid1",
    script: "/home/root/projects/takhfid1/.venv/bin/gunicorn",
    args: "-w 3 -k gthread --threads 4 --timeout 120 --bind 127.0.0.1:4008 'app:create_app()'",
    interpreter: "none",
    autorestart: true,
    max_restarts: 10,
    restart_delay: 3000,
    time: true,
    env: {
      PYTHONUNBUFFERED: "1"
    }
  }]
};
