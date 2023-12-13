module.exports = {
  apps : [{
    name: "openssh",
    interpreter: "none",
    script: "/usr/sbin/sshd",
    args: [
      "-D", "-e"
    ],
    watch: false,
    pid_file: "/var/run/sshd.pid",
    log_date_format: "YYYY-MM-DDTHH:mm:ss"
  }]
}
