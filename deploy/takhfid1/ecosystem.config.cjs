module.exports = {
  apps: [{
    name: "takhfid1",
    cwd: "/home/root/projects/takhfid1",
    script: "/bin/bash",
    args: "/home/root/projects/takhfid1/deploy/takhfid1/run.sh",
    interpreter: "none",
    autorestart: true,
    max_restarts: 10,
    restart_delay: 3000,
    time: true
  }]
};
