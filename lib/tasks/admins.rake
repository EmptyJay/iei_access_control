namespace :admins do
  desc "Create an admin account: admins:create[name,username,password,role]"
  task :create, [ :name, :username, :password, :role ] => :environment do |_, args|
    role = args[:role].presence || "admin"
    admin = Admin.new(
      name:     args[:name],
      username: args[:username],
      password: args[:password],
      role:     role,
      active:   true
    )
    if admin.save
      puts "Created #{role} account for #{admin.name} (#{admin.username})"
    else
      puts "Failed: #{admin.errors.full_messages.join(", ")}"
      exit 1
    end
  end
end
