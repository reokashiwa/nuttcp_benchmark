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

def remote_file_exist?(ssh, remotehost, file)
  return exec_command_remotehost(ssh, remotehost, "[ -e " + file + " ];echo \$?")
end

def detect_remote_os(commands, remotehost)
  ssh = commands["ssh"]
  return "redhat" if remote_file_exist?(ssh, remotehost, "/etc/redhat-release")
  return "ubuntu" if remote_file_exist?(ssh, remotehost, "/etc/lsb-release")
  return "debian" if remote_file_exist?(ssh, remotehost, "/etc/debian_version")
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

def set_link_mtu_remotehost(commands, remotehost, link, mtu)
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

def set_cpufreq(link, commands, governer)
  numa_node_file = "/sys/class/net/" + link + "/device/numa_node"
  if File.exist?(numa_node_file)
    File.open(numa_node_file){|file|
      numa_node = file.gets
    }
  else
    p "numa_node file does not exist."
    exit(1)
  end

  exec_command(commands["lscpu"]).each_line do |line|
    if line.include?("NUMA node" + numa_node)
      numa_cpus_range = line.split(' ')[4].gsub(',', "\n")
      break
    end
  end

  if numa_cpus_range != nil
    numa_cpus_range.each_line do |line|
      if line.include?("-")
        for num in line.split("-")[0]..line.split("-")[1]
          case detect_os
          when "redhat" then
            command = [commands["sudo"], commands["cpupower"], "-c", num, "frequency-set",
                       "-g", governer]
          else
            command = [commands["sudo"], commands["cpufreq_set"], "-c", num, 
                       "-g", governer]
          end
          exec_command(command)
        end
      else
        # if line does not include "-" == only number
        # (to implement)
      end
    end
  else
    p "numa_cpu can not be found."
    exit(1)
  end
end

def set_cpufreq_remote(commands, remotehost, link, governer)
  numa_node_file = "/sys/class/net/" + link + "/device/numa_node"

  ssh = commands["ssh"]
  if remote_file_exist?(ssh, remotehost, numa_node_file)
    numa_node = exec_command_remotehost(ssh, remotehost, ["/bin/cat", numa_node_file].join(" "))
  else
    p "numa_node file does not exist."
    exit(1)
  end

  exec_command_remotehost(ssh, remotehost, commands["lscpu_remote"]).each_line do |line|
    if line.include?("NUMA node" + numa_node)
      numa_cpus_range = line.split(' ')[4].gsub(',', "\n")
      break
    end
  end

  if numa_cpus_range != nil
    numa_cpus_range.each_line do |line|
      if line.include?("-")
        for num in line.split("-")[0]..line.split("-")[1]
          case detect_os
          when "redhat" then
            command = [commands["sudo_remote"], commands["cpupower_remote"], "-c", num,
                       "frequency-set_remote", "-g", governer]
          else
            command = [commands["sudo_remote"], commands["cpufreq_set_remote"], "-c", num, 
                       "-g", governer]
          end
          exec_command_remote(ssh, remotehost, command)
        end
      else
        # if line does not include "-" == only number
        # (to implement)
      end
    end
  else
    p "numa_cpu can not be found."
    exit(1)
  end
end

link = conf["target_link"]
link_remotehost = conf["target_link_remotehost"]
remotehost = conf["target_remotehost"]
benchmark_parameter = conf["benchmark_parameter"]
tcp_parameter=conf["tcp_parameter"]
commands = make_commands

initial_mtu = link_mtu(commands, target_link)

conf["target_mtu"].each{|mtu|
  # NORMAL
  set_link_mtu(commands, ink, mtu)
  killall_nuttcp_remotehost(remotehost)
  set_link_mtu_remotehost(commands, remotehost, link_remotehost, mtu)
  start_nuttcpd_remotehost(commands, remotehost)
  benchmark(commands, remotehost, benchmark_parameter) # repeat number...

  # CPUFREQ
  set_cpufreq(commands, link, "performance")
  killall_nuttcp_remotehost(remotehost)
  set_cpufreq_remote(commands, remotehost, link_remotehost) # to_implement
  start_nuttcpd_remotehost(commands, remotehost)
  benchmark(commands, remotehost, benchmark_parameter) 

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
