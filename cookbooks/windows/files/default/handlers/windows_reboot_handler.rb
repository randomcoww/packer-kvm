#
# Author:: Seth Chisamore (<schisamo@chef.io>)
# Copyright:: Copyright (c) 2011 Chef Software, Inc
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class WindowsRebootHandler < Chef::Handler
  include Chef::Mixin::ShellOut

  def initialize(allow_pending_reboots = true, timeout = 60, reason = 'Chef client run')
    @allow_pending_reboots = allow_pending_reboots
    @timeout = timeout
    @reason = reason
  end

  def report
    log_message, reboot = begin
      if reboot_requested?
        ["chef_handler[#{self.class}] requested reboot will occur in #{timeout} seconds", true]
      elsif reboot_pending?
        if @allow_pending_reboots
          ["chef_handler[#{self.class}] reboot pending - automatic reboot will occur in #{timeout} seconds", true]
        else
          ["chef_handler[#{self.class}] reboot pending but handler not configured to act on pending reboots - please reboot node manually", false]
        end
      else
        ["chef_handler[#{self.class}] no reboot requested or pending", false]
      end
    end

    Chef::Log.warn(log_message)
    shell_out!("shutdown /r /t #{timeout} /c \"#{reason}\"") if reboot
  end

  private

  # reboot cause CHEF says so:
  # reboot explicitly requested in our cookbook code
  def reboot_requested?
    node.run_state[:reboot_requested] == true
  end

  if Chef::VERSION > '11.12'
    include Chef::DSL::RebootPending
  else
    # reboot cause WIN says so:
    # reboot pending because of some configuration action we performed
    def reboot_pending?
      # this key will only exit if the system need a reboot to update some file currently in use
      # see http://technet.microsoft.com/en-us/library/cc960241.aspx
      Registry.value_exists?('HKLM\SYSTEM\CurrentControlSet\Control\Session Manager', 'PendingFileRenameOperations') ||
        # 1 for any value means reboot pending
        # "9306cdfc-c4a1-4a22-9996-848cb67eddc3"=1
        (Registry.key_exists?('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') &&
          Registry.get_values('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired').select { |v| v[2] == 1 }.any?) ||
        # this key will only exit if the system is pending a reboot
        ::Registry.key_exists?('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') ||
        # 1, 2 or 3 for 'Flags' value means reboot pending
        (Registry.key_exists?('HKLM\SOFTWARE\Microsoft\Updates\UpdateExeVolatile') &&
          [1, 2, 3].include?(Registry.get_value('HKLM\SOFTWARE\Microsoft\Updates\UpdateExeVolatile', 'Flags')))
    end
  end

  def timeout
    node.run_state[:reboot_timeout] || node['windows']['reboot_timeout'] || @timeout
  end

  def reason
    node.run_state[:reboot_reason] || @reason
  end
end
