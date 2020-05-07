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

def detect_os
  return "redhat" if File.exist?("/etc/redhat-release")
  return "ubuntu" if File.exist?("/etc/lsb-release")
  return "debian" if File.exist?("/etc/debian_version")
end

def make_commands
  required_commands = ["ip", "lscpu", "sudo", "sysctl", "ssh", "killall", "nuttcp"]
  required_commands.push("cpufreq-set") if detect_os == "ubuntu"
  required_commands.push("cpupower") if detect_os == "redhat"

  commands = Hash.new
  required_commands.each{|command|
    commands[command] = which(command)
  }
  return command
end

def link_mtu(commands, link)
  command = commands["ip"] + " link show " + link
  Open3.popen3() do |stdin, stdout, stderr, status|
    if status.value.to_i == 0
      return stdout.gets.strip.split(' ')[5]
    else
      p stderr
      exit(1)
    end
  end
end

commands = make_commands
p link_mtu(commands, conf["link"])
conf["target"].each{|mtu|
  
}
