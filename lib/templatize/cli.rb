module Templatize
  class CLI < Thor

    @@vconnection = nil
    @@template    = nil
    @@vm          = nil

    class_option 'debug',           :type => :boolean, :default  => false,         :desc  => 'Enable debug output'
    class_option 'template-folder', :type => :string,  :required => true,          :desc  => 'The location that you store templates, including datacenter'
    class_option 'distro',          :type => :string,  :default  => 'debian',      :desc  => 'Linux distobution of the template'
    class_option 'distro-version',  :type => :string,  :required => true,          :desc  => 'Version of the Linux disto'
    class_option 'template-slug',   :type => :string,  :default  => 'templatized', :desc  => 'The identifying slug for templates built using this system'

    desc 'get_vm', 'Gets our vm object'
    def get_vm

      folder_components = options[:'template-folder'].split('/')

      folder = nil

      folder_components.each do |fc|
        unless folder
          folder = @@vconnection[:dc].vmFolder.find(fc, RbVmomi::VIM::Folder)
        else
          folder = folder.find(fc, RbVmomi::VIM::Folder)
        end
      end

      vm = (
        folder.children.find_all do |v|
          v.name =~ /#{options[:disto]}-#{options[:'distro-version']}-#{options[:'template-slug']}.*/ and v.config.template == false
        end
      )

      @@vm = vm

    end

    desc 'templatize', 'Converts back to a template'
    def templatize

      @@vm.PowerOffVM_Task

      hdd = (
        @@vm.config.hardware.device.find do |h|
          h.is_a?(RbVmomi::VIM::VirtualDisk) and (h.deviceInfo.label == 'Hard disk 1')
        end
      ).key

      @@vm.ReconfigVM_Task(
        :spec => {
          :bootOptions => {
            :bootOrder => [
              RbVmomi::VIM::VirtualMachineBootOptionsBootableDiskDevice.new(:deviceKey => hdd)]
          }
        }
      )

      @@vm.Rename_Task(:newName => "#{options[:distro]}-#{options[:'distro-version']}-#{options[:'template-slug']}-#{Date.today.strftime('%Y%m%d')}")

      @@vm.MarkAsTemplate

    end

    desc 'get_template', 'Gets our template object'
    def get_template

      folder_components = options[:'template-folder'].split('/')

      folder = nil

      folder_components.each do |fc|
        unless folder
          folder = @@vconnection[:dc].vmFolder.find(fc, RbVmomi::VIM::Folder)
        else
          folder = folder.find(fc, RbVmomi::VIM::Folder)
        end
      end

      template = (
        folder.children.find_all do |t|
          t.name =~ /#{options[:disto]}-#{options[:'distro-version']}-#{options[:'template-slug']}.*/ and t.config.template == true
        end
      )

      @@template = template

    end

    desc 'prepare', 'Prepares our template for reloading.'
    method_option 'vcenter-cluster', :type => :string, :required => true, :desc => 'Which cluster to deploy the template to for reloading'
    def prepare

      @@template.first.MarkAsVirtualMachine(
        :pool => @@vconnection[:dc].find_compute_resource([]).find(
          options[:'vcenter-cluster'], RbVmomi::VIM::ClusterComputeResource
        ).resourcePool
      )

      hdd = (
        @@template.config.hardware.device.find do |h|
          h.is_a?(RbVmomi::VIM::VirtualDisk) and (h.deviceInfo.label == 'Hard disk 1')
        end
      ).key

      nic = (
        @@template.config.hardware.device.find do |h|
          h.is_a?(RbVmomi::VIM::VirtualEthernetCard) and (h.deviceInfo.label == 'Network adapter 1')
        end
      ).key

      @@template.ReconfigVM_Task(
        :spec => {
          :bootOptions => {
            :bootOrder => [
              RbVmomi::VIM::VirtualMachineBootOptionsBootableEthernetDevice.new(:deviceKey => nic),
              RbVmomi::VIM::VirtualMachineBootOptionsBootableDiskDevice.new(:deviceKey => hdd)]
          }
        }
      )

    end

    desc 'vconnect', 'Builds a connection to vCenter'
    method_option 'vcenter-user',   :type => :string, :required => true, :desc => 'The user used to log into vCenter'
    method_option 'vcenter-passwd', :type => :string, :required => true, :desc => 'The password used for your vCenter user'
    method_option 'vcenter-server', :type => :string, :required => true, :desc => 'Hostname of your vCenter instance'
    def vconnect

      vim = RbVmomi::VIM.connect(
        :host     => options[:'vcenter-server'],
        :user     => options[:'vcenter-user'],
        :password => options[:'vcenter-passwd'],
        :ssl      => true,
        :insecure => true,
        :rev      => '5.0'
      )

      dc = vim.serviceInstance.find_datacenter(options[:'template-folder'].split('/')[0])

      @@vconnection = { :vim => vim, :dc => dc }
    end

    desc 'derazor', 'Removes the bound policy from razor'
    method_option 'razor-server', :type => :string, :required => true, :desc => 'Which razor api endpoint to interact with'
    def derazor

      mac = (
        @@template.config.hardware.device.find do |h|
          h.is_a?(RbVmomi::VIM::VirtualEthernetCard) and (h.deviceInfo.label == 'Network adapter 1')
        end
      ).macAddress.upcase

      nodes = JSON.parse(RestClient.get("http://#{options[:'razor-server']}:8026/razor/api/node/get"))

      template_uuid = nil

      nodes['response'].each do |node|
        attributes = JSON.parse(RestClient.get("http://#{options[:'razor-server']}:8026/razor/api/node/get/#{node['@uuid']}"))
          if attributes['response'][0]['@attributes_hash']['macaddress_eth0'] == mac
            template_uuid = node['@uuid']
          end
      end

      active_models = JSON.parse(RestClient.get("http://#{options[:'razor-server']}:8026/razor/api/policy/get/active_model"))

      active_uuid = nil

      active_models['response'].each do |active|
        attributes = JSON.parse(RestClient.get("http://#{options[:'razor-sever']}:8026/razor/api/policy/get/active_model/#{active['@uuid']}"))
        if attributes['response'][0]['@node_uuid'] == template_uuid
          active_uuid = active['@uuid']
        end
      end

      RestClient.get("http://#{options[:'razor-server']}:8026/razor/api/policy/remove/active_model/#{active_uuid}")

    end

    desc 'in_matchers', 'Makes sure that our mac is in the proper match group or adds it'
    def in_matchers
      # noop...for now since I haven't identified the API calls for this yet.
    end

    desc 'boot', 'Pretty simple...turns on the VM so it can boot'
    def boot
      @@template.PowerOnVM_Task
    end

    desc 'rebuild', 'Kicks off our template rebuild'
    def rebuild

      invoke :vconnect
      invoke :get_template
      invoke :prepare
      invoke :derazor
      invoke :in_matchers
      invoke :boot

    end

    desc 'finish', 'Post load action that gets us back to usable template.'
    def finish

      invoke :vconnect
      invoke :get_vm
      invoke :templatize

    end
  end
end
