#!/Users/reo/.rbenv/shims/ruby

require "open3"
require "yaml"
require 'optparse'

opt = OptionParser.new
OPTS = Hash.new
OPTS[:configfile] = "config.yaml"
opt.on('-c VAL', '--configfile VAL') {|v| OPTS[:configfile] = v}
opt.parse!(ARGV)
conf = YAML.load_file(OPTS[:configfile])

def which(command)
  Open3.popen3("which "+command) do |stdin, stdout, stderr, status|
    if status.value.to_i == 0
      return stdout.gets.strip
    else
      p command+" is not installed."
      exit(1)
    end
  end
end

def which_remotehost(commands, remotehost, command)
  Open3.popen3([commands["ssh"], remotehost, "which", command).join(" ") do
                 |stdin, stdout, stderr, status|
                 if status.value.to_i == 0
                   return stdout.gets.strip
                 else
                   p command+" is not installed."
                   exit(1)
                 end
               end
end

def exec_command(command)
  Open3.popen3(command) do |stdin, stdout, stderr, status|
    if status.value.to_i == 0
      return stdout
    else
      p stderr
      exit(1)
    end
  end
end

def exec_command_remotehost(ssh, remotehost, command)
  command = [ssh, remotehost, command].join(" ")
  return exec_command(command)
end

def detect_os
  return "redhat" if File.exist?("/etc/redhat-release")
  return "ubuntu" if File.exist?("/etc/lsb-release")
  return "debian" if File.exist?("/etc/debian_version")
end

def detect_remote_os(commands, remotehost)
  return "redhat" if exec_command_remotehost(commands["ssh"], remotehost, "[ -e /etc/redhat-release ];echo \$?")
  return "ubuntu" if exec_command_remotehost(commands["ssh"], remotehost, "[ -e /etc/lsb-release ];echo \$?")
  return "debian" if exec_command_remotehost(commands["ssh"], remotehost, "[ -e /etc/debian_version ];echo \$?")
end

def make_commands(remotehost)
  required_commands = ["ip", "lscpu", "sudo", "sysctl", "ssh", "killall", "nuttcp"]
  required_commands.push("cpufreq-set") if detect_os == "ubuntu"
  required_commands.push("cpupower") if detect_os == "redhat"

  commands = Hash.new
  required_commands.each{|command|
    commands[command] = which(command)
    commands[command + "_remote"] = which_remote(command, remotehost)
  }
  return command
end

def link_mtu(commands, link)
  command = [commands["ip"], "link show", link].join(" ")
  link exec_command(command).gets.strip.split(' ')[5]
end

def link_mtu_remotehost(commands, link, remotehost)
  command = [commands["ip"], "link show", link].join(" ")
  return exec_command_remotehost(commands["ssh"], remotehost, command).gets.strip.split(' ')[5]
end

def set_link_mtu(commands, link, mtu)
  command = [commands["sudo"], commands["ip"], "link set", link, "mtu", mtu].join(" ")
  return exec_command(command)
end

def set_link_mtu_remotehost(commands, link, mtu)
  command = [commands["sudo"], commands["ip"], "link set", link, "mtu", mtu].join(" ")
  return exec_command_remotehost(commands["ssh"], remotehost, command)
end

def killall_nuttcp_remotehost(commands, remotehost)
  command = [commands["killall_remote"], commands["nuttcp_remote"]].join(" ")
  return exec_command_remotehost(commands["ssh"], remotehost, command)
end

def start_nuttcpd_remotehost(commands, remotehost)
  command = [commands["nuttcp_remote"], "-S"].join(" ")
  return exec_command_remotehost(commands["ssh"], remotehost, command)
end

def benchmark(commands, remotehost, parameter)
  command = [commands["nuttcp"], "-xc 7/7 -T" + parameter["xmit_timeout"], remotehost].join(" ")
  return exec_command(command)
end

link = conf["target_link"]
link_remotehost = conf["target_link_remotehost"]
remotehost = conf["target_remotehost"]
parameter = conf["benchmark_parameter"]
commands = make_commands

initial_mtu = link_mtu(commands, target_link)

conf["target_mtu"].each{|mtu|
  # NORMAL
  set_link_mtu(commands, ink, mtu)
  killall_nuttcp_remotehost(remotehost)
  set_link_mtu_remotehost(remotehost, link_remotehost, mtu)
  start_nuttcpd_remotehost(commands, remotehost)
  benchmark(commands, remotehost, parameter) # repeat number...

  # CPUFREQ
  set_cpufreq(commands, "performance") # to_implement
  killall_nuttcp_remotehost(remotehost)
  set_cpufreq_remote(commands, remotehost, "performance") # to_implement
  start_nuttcpd_remotehost(commands, remotehost)
  benchmark(commands, remotehost, parameter) 

  # TCP BUFFERS
  set_tcp_buffers(tcp_parameter) # to_implement
  killall_nuttcp_remotehost(remotehost)
  set_tcp_buffers_remote(commands, remotehost, tcp_parameter) # to_implement
  start_nuttcpd_remotehost(commands, remotehost)
  benchmark_window_size(commands, remotehost, tcp_parameter) # to_implement

  # reset
  set_cpufreq(commands, "powersave")
  set_cpufreq_remote(commands, remotehost, "powersave")
  set_tcp_buffers(initial_tcp_parameter)
  set_tcp_buffers_remote(commands, remotehost, initial_tcp_parameter)
}

# restore
set_link_mtu(commands, link, initial_mtu)
set_link_mtu_remotehost(remotehost, link_remotehost, initial_mtu)
killall_nuttcp_remotehost(remotehost)
