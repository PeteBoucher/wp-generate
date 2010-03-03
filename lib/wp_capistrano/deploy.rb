require 'wp_config'
require 'erb'
require 'digest'
require 'digest/sha1'
Capistrano::Configuration.instance.load do
  default_run_options[:pty] = true

  # Load from config
  set :wordpress_version, WPConfig.wordpress.version
  set :application, WPConfig.application.name
  set :repository, WPConfig.application.repository
  set :domain, WPConfig.deploy.staging.ssh_domain
  set :user, WPConfig.deploy.staging.ssh_user
  set :deploy_to, WPConfig.deploy.staging.path
  set :wordpress_domain, WPConfig.deploy.staging.vhost
  set :wordpress_db_name, WPConfig.deploy.staging.database.name
  set :wordpress_db_user, WPConfig.deploy.staging.database.user
  set :wordpress_db_password, WPConfig.deploy.staging.database.password
  set :wordpress_db_host, WPConfig.deploy.staging.database.host
  set :use_sudo, WPConfig.deploy.staging.use_sudo

  # Everything else
  set :scm, "git"
  set :deploy_via, :remote_cache
  set :branch, "master"
  set :git_shallow_clone, 1
  set :git_enable_submodules, 1
  set :wordpress_db_host, "localhost"
  set :wordpress_git_url, "git@git.private.thedextrousweb.com:wordpress/wordpress.git"
  set :wordpress_auth_key, Digest::SHA1.hexdigest(rand.to_s)
  set :wordpress_secure_auth_key, Digest::SHA1.hexdigest(rand.to_s)
  set :wordpress_logged_in_key, Digest::SHA1.hexdigest(rand.to_s)
  set :wordpress_nonce_key, Digest::SHA1.hexdigest(rand.to_s)

  #allow deploys w/o having git installed locally
  set(:real_revision) do
    output = ""
    invoke_command("git ls-remote #{repository} #{branch} | cut -f 1", :once => true) do |ch, stream, data|
      case stream
      when :out
        if data =~ /\(yes\/no\)\?/ # first time connecting via ssh, add to known_hosts?
          ch.send_data "yes\n"
        elsif data =~ /Warning/
        elsif data =~ /yes/
          #
        else
          output << data
        end
      when :err then warn "[err :: #{ch[:server]}] #{data}"
      end
    end
    output.gsub(/\\/, '').chomp
  end

  #no need for log and pids directory
  set :shared_children, %w(system)

  role :app, domain
  role :web, domain
  role :db,  domain, :primary => true

  namespace :deploy do
    desc "Override deploy restart to not do anything"
    task :restart do
      #
    end

    task :finalize_update, :except => { :no_release => true } do
      run "chmod -R g+w #{latest_release}"

      # I've got submodules in my submodules
      #run "cd #{latest_release} && git submodule foreach --recursive git submodule update --init"
      # Git 1.5-compatability:
      run "cd #{latest_release} && DIR=`pwd` && for D in `grep '^\\[submodule' .git/config | cut -d\\\" -f2`; do cd $DIR/$D && git submodule init && git submodule update; done"

      system("sass themes/#{application}/style/style.sass > themes/#{application}/style/sass_output.css")
      top.upload("themes/#{application}/style/sass_output.css", "#{latest_release}/themes/#{application}/style/" , :via => :scp)

      run <<-CMD
        sed -i 's/\.php/\.css/' #{latest_release}/themes/#{application}/style.css &&

        mkdir -p #{latest_release}/finalized &&
        cp -rv   #{shared_path}/wordpress/*     #{latest_release}/finalized/ &&
        cp -rv   #{shared_path}/wp-config.php   #{latest_release}/finalized/wp-config.php &&
        cp -rv   #{shared_path}/htaccess        #{latest_release}/finalized/.htaccess &&
        rm -rf   #{latest_release}/finalized/wp-content &&
        mkdir    #{latest_release}/finalized/wp-content &&
        ls #{latest_release} && cp -rv #{latest_release}/themes  #{latest_release}/finalized/wp-content/ ;
        ls #{latest_release} && cp -rv #{latest_release}/plugins #{latest_release}/finalized/wp-content/ ;
        ls #{latest_release} && cp -rv #{latest_release}/uploads #{latest_release}/finalized/wp-content/ ;
        rm -f #{latest_release}/finalized/wp-content/uploads/dump.sql.gz ;
        true
      CMD
    end

    task :symlink, :except => { :no_release => true } do
      on_rollback do
        if previous_release
          run "rm -f #{current_path}; ln -s #{previous_release}/finalized #{current_path}; true"
        else
          logger.important "no previous release to rollback to, rollback of symlink skipped"
        end
      end

      run "rm -f #{current_path} && ln -s #{latest_release}/finalized #{current_path}"
    end
  end

  namespace :setup do

    desc "Setup this server for a new wordpress site."
    task :wordpress do
      "mkdir -p #{deploy_to}"
      deploy.setup
      wp.config
      wp.htaccess
      wp.checkout
      setup.mysql
    end

    desc "Creates the DB, and loads the dump"
    task :mysql do
      upload("uploads/dump.sql.gz", shared_path, :via => :scp)
      run <<-CMD
        test #{wordpress_db_name}X != `echo 'show databases' | mysql -u root | grep '^#{wordpress_db_name}$'`X &&
        echo 'create database if not exists `#{wordpress_db_name}`' | mysql -u root &&
        zcat #{shared_path}/dump.sql.gz | sed 's/localhost/#{wordpress_domain}/g' | mysql -u root #{wordpress_db_name} || true
      CMD
    end

  end

  namespace :wp do

    desc "Checks out a copy of wordpress to a shared location"
    task :checkout do
      run "rm -rf #{shared_path}/wordpress || true"
      run "git clone --depth 1 #{wordpress_git_url} #{shared_path}/wordpress"
      run "cd #{shared_path}/wordpress && git fetch --tags && git checkout v#{wordpress_version}"
    end

    desc "Sets up wp-config.php"
    task :config do
      file = File.join(File.dirname(__FILE__), "wp-config.php.erb")
      template = File.read(file)
      buffer = ERB.new(template).result(binding)

      put buffer, "#{shared_path}/wp-config.php"
      puts "New wp-config.php uploaded! Please run cap:deploy to activate these changes."
    end

    desc "Sets up .htaccess"
    task :htaccess do
      run 'env echo -e \'<IfModule mod_rewrite.c>\nRewriteEngine On\nRewriteBase /\nRewriteCond %{REQUEST_FILENAME} !-f\nRewriteCond %{REQUEST_FILENAME} !-d\nRewriteRule . /index.php [L]\n</IfModule>\' > '"#{shared_path}/htaccess"
    end

  end

end