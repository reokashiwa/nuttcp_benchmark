#!/bin/sh
exec ruby -x "$0" "$@"
#!ruby

require "open3"
require "yaml"
require 'optparse'

opt = OptionParser.new
OPTS = Hash.new
OPTS[:configfile] = "config.yaml"
opt.on('-c VAL', '--configfile VAL') {|v| OPTS[:configfile] = v}
opt.parse!(ARGV)
conf = YAML.load_file(OPTS[:configfile])

class Benchmark
  def initialize(conf)
    @link = conf["target_link"]
    @link_remotehost = conf["target_link_remotehost"]
    @remotehost = conf["target_remotehost"]
    @benchmark_parameter = conf["benchmark_parameter"]
    @tcp_parameters=conf["tcp_parameters"]
    @commands = make_commands
    @tcp_parameter_combinations = {"rmem_max" => "net.core.rmem_max",
                                   "wmem_max" => "net.core.wmem_max", 
                                   "tcp_rmem" => "net.ipv4.tcp_rmem",
                                   "tcp_wmem" => "net.ipv4.tcp_wmem"}
    
    print "@link: " + @link + "\n"
    print "@link_remotehost: " + @link_remotehost + "\n"
    print "@remotehost: " + @remotehost + "\n"
    print "@commands: "
    p @commands
  end

  def exec_command(command)
    Open3.popen3(command) do |stdin, stdout, stderr, status|
      if status.value.to_i == 0
        return stdout.dup
      else
        stderr.each do |line| p line end
        exit(1)
      end
    end
  end

  def exec_command_remotehost(remotehost_command)
    command = [which("ssh"), @remotehost, remotehost_command].join(" ")
    return exec_command(command)
  end
  
  def remote_file_exist?(filename)
    result = exec_command_remotehost('"[ -e ' + filename + ' ];echo \$?"')
    result.each do |line|
      if line.strip == "1"
        return false
      else
        return true
      end
    end
  end

  def detect_os
    return "redhat" if File.exist?("/etc/redhat-release")
    return "ubuntu" if File.exist?("/etc/lsb-release")
    return "debian" if File.exist?("/etc/debian_version")
  end

  def detect_remote_os
    return "redhat" if remote_file_exist?("/etc/redhat-release") 
    return "ubuntu" if remote_file_exist?("/etc/lsb-release")
    return "debian" if remote_file_exist?("/etc/debian_version")
  end

  def which(command)
    Open3.popen3(["which", command].join(" ")) do |stdin, stdout, stderr, status|
      if status.value.to_i == 0
        return stdout.gets.strip
      else
        stderr.each do |line| p line end
        exit(1)
      end
    end
  end

  def which_remotehost(command)
    Open3.popen3([which("ssh"), @remotehost, "/bin/bash which", command].join(" ")) do |stdin, stdout, stderr, status|
      if status.value.to_i == 0
        return stdout.gets.strip
      else
        stderr.each do |line| p line end
        exit(1)
      end
    end
  end
  
  def make_commands
    commands = Hash.new
    required_commands = ["ip", "lscpu", "sudo", "sysctl", "killall", "nuttcp"]
    required_remote_commands = Marshal.load(Marshal.dump(required_commands))

    if detect_os == "redhat"
      required_commands.push("cpupower")
    else
      required_commands.push("cpufreq-set")
    end

    commands["ssh"] = which("ssh")

    if detect_remote_os == "redhat"
      required_remote_commands.push("cpupower")
    else
      required_remote_commands.push("cpufreq-set")
    end
    
    required_commands.each{|command|
      commands[command] = which(command)
    }

    required_remote_commands.each{|command|
      commands[command + "_remote"] = which_remotehost(command)
    }

    return commands
  end

  def show_link_mtu
    command = [@commands["ip"], "link show", @link].join(" ")
    return exec_command(command).gets.strip.split(' ')[4]
  end

  def show_link_mtu_remotehost
    command = [@commands["ip"], "link show", @link_remotehost].join(" ")
    return exec_command_remotehost(command).gets.strip.split(' ')[4]
  end

  def set_link_mtu(mtu)
    command = [@commands["sudo"], @commands["ip"], "link set", @link, "mtu", mtu].join(" ")
    result = exec_command(command)
    sleep(1)
    return result
  end

  def set_link_mtu_remotehost(mtu)
    command = [@commands["sudo"], @commands["ip"], "link set", @link_remotehost, "mtu", mtu].join(" ")
    result = exec_command_remotehost(command)
    sleep(1)
    return result
  end

  def show_tcp_parameters
    parameters = Hash.new
    @tcp_parameter_combinations.each {|key, value|
      result = exec_command([@commands["sysctl"], "-n", value].join(" "))
      result.each{|line|
        parameters[key] = line.strip.gsub(/\t/, ' ')
        next
      }
    }
    return parameters
  end

  def show_tcp_parameters_remotehost
    parameters = Hash.new
    @tcp_parameter_combinations.each {|key, value|
      result = exec_command_remotehost([@commands["sysctl"], "-n", value].join(" "))
      result.each{|line|
        parameters[key] = line.strip.gsub(/\t/, ' ')
        next
      }
    }
    return parameters
  end

  def set_tcp_parameters(tcp_parameters)
    @tcp_parameter_combinations.each {|key, value|
      command = [@commands["sudo"], @commands["sysctl"], "-w",
                 value + "=" + tcp_parameters["rmem_max"]].join(" ")
      exec_command(command)
    }
  end

  def set_tcp_parameters_remotehost(tcp_parameters)
    @tcp_parameter_combinations.each {|key, value|
      command = [@commands["sudo"], @commands["sysctl"], "-w",
                 value + "=" + tcp_parameters["rmem_max"]].join(" ")
      exec_command_remotehost(command)
    }
  end

  def killall_nuttcpd_remotehost
    command = [@commands["killall_remote"], @commands["nuttcp_remote"]].join(" ")
    return exec_command_remotehost(command)
  end

  def start_nuttcpd_remotehost
    command = [@commands["nuttcp_remote"], "-S"].join(" ")
    return exec_command_remotehost(command)
  end

  def exec(parameters)
    option_combinations = {
      "dscp_value" => "c",
      "buffer_len" => "l",
      "num_bufs" => "n",
      "window_size" => "w",
      "server_window" => "ws",
      "braindead" => "wb",
      "data_port" => "p",
      "control_port" => "P",
      "num_streams" => "N",
      "xmit_rate_limit" => "R",
      "xmit_timeout" => "T",
      "cpu_affinity" => "x"}

    options = String.new
    option_combinations.each{|key, value|
      if parameters.has_key?(key)
        options = options + "-" + value + parameters[key] + " "
      end
    }
    
    command = [@commands["nuttcp"], options, @remotehost].join(" ")
    result = exec_command(command)
    result.each{|line|
      return line.strip.split(/\s+/)[6] 
    }
  end
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

# conf["target_mtu"].each{|mtu|
#   # NORMAL
#   set_link_mtu(commands, ink, mtu)
#   killall_nuttcp_remotehost(remotehost)
#   set_link_mtu_remotehost(commands, remotehost, link_remotehost, mtu)
#   start_nuttcpd_remotehost(commands, remotehost)
#   benchmark(commands, remotehost, benchmark_parameter) # repeat number...

#   # CPUFREQ
#   set_cpufreq(commands, link, "performance")
#   killall_nuttcp_remotehost(remotehost)
#   set_cpufreq_remote(commands, remotehost, link_remotehost)
#   start_nuttcpd_remotehost(commands, remotehost)
#   benchmark(commands, remotehost, benchmark_parameter) 

#   # TCP BUFFERS
#   set_tcp_buffers(commands, tcp_parameters)
#   killall_nuttcp_remotehost(remotehost)
#   set_tcp_buffers_remote(commands, remotehost, tcp_parameters)
#   start_nuttcpd_remotehost(commands, remotehost)
#   benchmark_with_window_size(commands, remotehost, tcp_parameters) # to_implement

#   # reset
#   set_cpufreq(commands, "powersave")
#   set_cpufreq_remote(commands, remotehost, "powersave")
#   set_tcp_buffers(initial_tcp_parameters)
#   set_tcp_buffers_remote(commands, remotehost, initial_tcp_parameters)
# }

# # restore
# set_link_mtu(commands, link, initial_mtu)
# set_link_mtu_remotehost(remotehost, link_remotehost, initial_mtu)
# killall_nuttcp_remotehost(remotehost)

benchmark = Benchmark.new(conf)

mtu = benchmark.show_link_mtu
mtu_remotehost = benchmark.show_link_mtu_remotehost

p mtu
p mtu_remotehost

# benchmark.set_link_mtu(9000)
# benchmark.set_link_mtu_remotehost(9000)

# p benchmark.show_link_mtu
# p benchmark.show_link_mtu_remotehost

# benchmark.set_link_mtu(mtu)
# benchmark.set_link_mtu_remotehost(mtu_remotehost)

# p benchmark.show_link_mtu
# p benchmark.show_link_mtu_remotehost

original_tcp_parameters = benchmark.show_tcp_parameters
original_tcp_parameters_remotehost = benchmark.show_tcp_parameters_remotehost

p original_tcp_parameters
p original_tcp_parameters_remotehost

# sample_parameters = {"rmem_max" => "425984", 
#                      "wmem_max" => "425984", 
#                      "tcp_rmem" => "8192 242144 12582912", 
#                      "tcp_wmem" => "8192 32768 8388608"}

# benchmark.set_tcp_parameters(sample_parameters)
# benchmark.set_tcp_parameters_remotehost(sample_parameters)

# p benchmark.show_tcp_parameters
# p benchmark.show_tcp_parameters_remotehost

# benchmark.set_tcp_parameters(original_tcp_parameters)
# benchmark.set_tcp_parameters_remotehost(original_tcp_parameters_remotehost)

# p benchmark.show_tcp_parameters
# p benchmark.show_tcp_parameters_remotehost

benchmark.killall_nuttcpd_remotehost
benchmark.start_nuttcpd_remotehost

nuttcp_parameter = {"xmit_timeout" => "1",
                    "window_size" => "1m"}
p benchmark.exec(nuttcp_parameter)
