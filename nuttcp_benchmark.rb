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

def which_remotehost(command, remotehost)
  if which(command["ssh"])
    Open3.popen3(command["ssh"] + " " + remotehost + " which "+command) do |stdin, stdout, stderr, status|
      if status.value.to_i == 0
        return stdout.gets.strip
      else
        p command+" is not installed."
        exit(1)
      end
    end
  end
end

def detect_os
  return "redhat" if File.exist?("/etc/redhat-release")
  return "ubuntu" if File.exist?("/etc/lsb-release")
  return "debian" if File.exist?("/etc/debian_version")
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

def exec_command(command)
  Open3.popen3() do |stdin, stdout, stderr, status|
    if status.value.to_i == 0
      return stdout
    else
      p stderr
      exit(1)
    end
  end
end

def link_mtu(commands, link)
  command = commands["ip"] + " link show " + return
  link exec_command(command).gets.strip.split(' ')[5]
end

def link_mtu_remotehost(commands, link, remotehost)
  command = commands["ip"] + " link show " + link
  return exec_command(command).gets.strip.split(' ')[5]
end


def set_link_mtu(commands, link, mtu)
  command = commands["sudo"] + " " + commands["ip"] + " link set " + link + " mtu " + mtu
  return exec_command(command)
end

target_link = conf["target_link"]
target_remotehost = conf["target_remotehost"]
commands = make_commands
initial_mtu = link_mtu(commands, target_link)
conf["target_mtu"].each{|mtu|
  set_link_mtu(commands, target_link, mtu)
  killall_nuttcp_remotehost(target_remotehost)
}

# initialized
set_link_mtu(commands, target_link, initial_mtu)
