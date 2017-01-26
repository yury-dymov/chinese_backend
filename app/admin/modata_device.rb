ActiveAdmin.register ModataDevice do
  config.sort_order = "state_asc"  
  config.filters = false
  actions :all, :except => [:new]
  
  index title: "Devices"
  menu label: proc{"Devices (#{ModataDevice.count})"}
end

