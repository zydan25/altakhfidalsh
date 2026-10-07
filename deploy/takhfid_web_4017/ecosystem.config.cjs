module.exports = {
  apps: [{
    name: "takhfid-web-4017",
    cwd: "/home/root/projects/takhfid_web_4017/current",
    script: "/home/root/projects/takhfid_web_4017/node_modules/serve/build/main.js",
    interpreter: "/usr/bin/node",
    args: "-s . -l 127.0.0.1:4017 --no-clipboard",
    autorestart: true,
    restart_delay: 2000,
    max_restarts: 10,
    time: true,
    env: { NODE_ENV: "production" }
  }]
};
