# ==================
# Main file for OpenAiExplorer
# ==================


require 'sketchup'
require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'stringio'


# ==================


module AS_Extensions

  module AS_OpenAIExplorer2016  

    # Set up some module-wide defaults as a hash
    @default_settings_hash = {
      "systemMessage" => "Generate only valid SketchUp 2016 Ruby code. Return Ruby code only, with no Markdown fences, no HTML, and no explanation. Operate only through the SketchUp Ruby API and in-memory Ruby data. Never access the local filesystem, the network, external processes, environment variables, or external applications.",  # System Message
      "aiModel" => "gpt-5.4-mini",  # Chat Completion Model
      "maxTokens" => "2048",  # Max. Tokens
      "temperature" => "0.2",  # Temperature
      "apiKey" => "",  # Provider API key forwarded through the local proxy
      "executeCode" => true,  # Execute code
      "submitModelView" => false,  # Submit model view with request
      "modelViewQuality" => "low",  # Model view submission quality
      "numPrompts" => "3",  # Number of submitted messages (user and assistant)
      "aiEndpoint" => "http://127.0.0.1:5000/sketchup",  # Local proxy endpoint
      "reasoning_effort" => "medium", # Reasoning effort: low, medium, high
      "showRawData" => false, # Show raw request/response data in the Ruby console
      "colorMode" => "light",  # Color mode
      "useCase" => "execute_ruby",  # Use case
      "useFunctionCalling" => false,  # Use function calling - Not used at this point
      "functionCallingJson" => "[]"  # Function calling JSON
    }
    
    # Create an empty array for all AI messages
    @ai_messages = []    

    # Track a single active dialog so only one can be open at a time
    @active_dialog = nil

    # Load all the system messages from a JSON file
    @system_msgs = {}
  
  
    # ==================
    
    # Helper to print debug output only when enabled in settings
    def self.puts_if_enabled(*args)
      settings = read_settings_hash
      if settings && settings["showRawData"]
        puts(*args)
      end
    end


    def self.load_system_messages
      file_path = File.join(__dir__, 'system_msgs.json')
      @system_msgs = {}

      begin
        file_content = File.read(file_path)
        @system_msgs = JSON.parse(file_content)
        raise "Invalid JSON format." unless @system_msgs.is_a?(Hash)
      rescue Errno::ENOENT
        puts "Error: File not found at #{file_path}."
      rescue JSON::ParserError => e
        puts "Error parsing JSON file: #{e.message}"
      rescue StandardError => e
        puts "An error occurred: #{e.message}"
      end
    end


    def self.default_system_message
      message = @system_msgs["execute_ruby"].to_s
      if message.strip == ""
        message = @default_settings_hash["systemMessage"].to_s
      end
      message
    end


    def self.normalize_settings(settings_hash)
      normalized = @default_settings_hash.merge(settings_hash || {})

      ["executeCode", "submitModelView", "showRawData", "useFunctionCalling"].each do |key|
        normalized[key] = case normalized[key]
                          when true, false
                            normalized[key]
                          else
                            normalized[key].to_s == "true"
                          end
      end

      normalized["systemMessage"] = default_system_message if normalized["systemMessage"].to_s.strip == ""
      normalized["useCase"] = "execute_ruby"
      normalized["executeCode"] = true
      normalized
    end


    def self.read_settings_hash
      settings = Sketchup.read_default(@extname, "ai_explorer_settings_hash", @default_settings_hash)
      normalize_settings(settings)
    rescue Exception
      normalize_settings(@default_settings_hash)
    end


    def self.persist_settings(settings_hash)
      settings = normalize_settings(read_settings_hash.merge(settings_hash || {}))
      Sketchup.write_default(@extname, "ai_explorer_settings_hash", settings)
      settings
    end

    def self.decode_dialog_argument(value)
      URI.decode_www_form_component(value.to_s)
    rescue Exception
      value.to_s
    end


    def self.parse_dialog_json(value)
      decoded = decode_dialog_argument(value)
      return {} if decoded.to_s.strip == ""

      JSON.parse(decoded)
    rescue JSON::ParserError
      {}
    end


    def self.dialog_file_path
      File.join(@extdir, @extname, 'as_openaiexplorer2016_ui.html')
    end


    def self.license_file_path
      File.join(@extdir, @extname, 'license_dlg.html')
    end


    def self.point_to_a(point)
      return nil unless point

      [point.x.to_f.round(4), point.y.to_f.round(4), point.z.to_f.round(4)]
    rescue Exception
      nil
    end


    def self.bounds_hash(bounds)
      return nil unless bounds

      {
        "min" => point_to_a(bounds.min),
        "max" => point_to_a(bounds.max),
        "width" => bounds.width.to_f.round(4),
        "height" => bounds.height.to_f.round(4),
        "depth" => bounds.depth.to_f.round(4)
      }
    rescue Exception
      nil
    end


    def self.entity_summary(entity)
      summary = {
        "type" => entity.typename.to_s,
        "name" => (entity.respond_to?(:name) ? entity.name.to_s : ""),
        "layer" => (entity.respond_to?(:layer) && entity.layer ? entity.layer.name.to_s : ""),
        "material" => (entity.respond_to?(:material) && entity.material ? entity.material.name.to_s : ""),
        "bounds" => (entity.respond_to?(:bounds) ? bounds_hash(entity.bounds) : nil)
      }

      if entity.respond_to?(:definition) && entity.definition
        summary["definition"] = entity.definition.name.to_s
      end

      if entity.respond_to?(:persistent_id)
        summary["persistent_id"] = entity.persistent_id rescue nil
      end

      summary
    rescue Exception => e
      { "type" => entity.class.to_s, "error" => e.message.to_s }
    end


    def self.collection_digest(collection, sample_limit, scan_limit)
      counts = Hash.new(0)
      sample = []
      scanned = 0

      collection.each do |entity|
        break if scanned >= scan_limit

        entity_type = entity.typename.to_s
        counts[entity_type] += 1
        sample << entity_summary(entity) if sample.length < sample_limit
        scanned += 1
      end

      {
        "count" => (collection.respond_to?(:length) ? collection.length : scanned),
        "scanned" => scanned,
        "truncated" => (collection.respond_to?(:length) ? collection.length > scanned : false),
        "counts_by_type" => counts,
        "sample" => sample
      }
    end


    def self.selection_digest(selection)
      items = []
      selection.each do |entity|
        break if items.length >= 25
        items << entity_summary(entity)
      end

      {
        "count" => selection.length,
        "items" => items
      }
    end


    def self.camera_hash(camera)
      return {} unless camera

      {
        "eye" => point_to_a(camera.eye),
        "target" => point_to_a(camera.target),
        "up" => point_to_a(camera.up),
        "fov" => (camera.respond_to?(:fov) ? camera.fov.to_f.round(4) : nil),
        "perspective" => (camera.respond_to?(:perspective?) ? camera.perspective? : nil)
      }
    rescue Exception
      {}
    end


    def self.scene_snapshot
      model = Sketchup.active_model
      view = model.active_view
      camera = view.camera

      {
        "app" => {
          "sketchup_version" => Sketchup.version.to_s,
          "ruby_version" => RUBY_VERSION,
          "platform" => RUBY_PLATFORM
        },
        "model" => {
          "title" => model.title.to_s,
          "path" => model.path.to_s,
          "bounds" => bounds_hash(model.bounds),
          "active_path" => (model.active_path || []).map { |entity| entity_summary(entity) },
          "selection" => selection_digest(model.selection),
          "active_entities" => collection_digest(model.active_entities, 30, 2000),
          "layers_count" => model.layers.length,
          "materials_count" => model.materials.length,
          "pages_count" => model.pages.length,
          "definitions_count" => model.definitions.length
        },
        "camera" => camera_hash(camera)
      }
    rescue Exception => e
      { "error" => e.message.to_s }
    end


    def self.system_prompt_for(settings)
      base_prompt = settings["systemMessage"].to_s
      if base_prompt.strip == "" || base_prompt.match(/html|markdown|body section|<pre>/i)
        base_prompt = default_system_message
      end

      hard_rules = [
        "Target SketchUp 2016 and Ruby 2.0.",
        "Return only executable Ruby code.",
        "Do not wrap the response in Markdown fences.",
        "Do not include HTML or natural-language explanation.",
        "Never access files, directories, sockets, URLs, environment variables, subprocesses, shell commands, or external applications.",
        "Limit all model changes to the active SketchUp model."
      ]

      ([base_prompt] + hard_rules).join(' ')
    end


    def self.build_proxy_request(settings, prompt, history)
      payload = {
        "mode" => "sketchup_ruby",
        "model" => settings["aiModel"].to_s,
        "prompt" => prompt.to_s,
        "system_prompt" => system_prompt_for(settings),
        "scene" => scene_snapshot,
        "history" => history,
        "options" => {
          "execute_code" => true,
          "max_tokens" => settings["maxTokens"].to_i,
          "temperature" => settings["temperature"].to_f,
          "reasoning_effort" => settings["reasoning_effort"].to_s,
          "num_prompts" => settings["numPrompts"].to_i,
          "return_format" => "ruby_only",
          "safety_mode" => "sketchup_only"
        }
      }

      if settings["apiKey"].to_s.strip != ""
        payload["api_key"] = settings["apiKey"].to_s
      end

      if settings["submitModelView"]
        payload["screenshot"] = {
          "mime_type" => "image/png",
          "detail" => settings["modelViewQuality"].to_s,
          "data" => encoded_screenshot,
          "source" => "active_view"
        }
      end

      payload
    end


    def self.extract_response_text(response_body)
      return response_body.to_s unless response_body.is_a?(Hash)

      return response_body["ruby"].to_s if response_body["ruby"].to_s.strip != ""
      return response_body["code"].to_s if response_body["code"].to_s.strip != ""
      return response_body["content"].to_s if response_body["content"].to_s.strip != ""
      return response_body["response"].to_s if response_body["response"].to_s.strip != ""

      if response_body["choices"].is_a?(Array) && response_body["choices"][0].is_a?(Hash)
        message = response_body["choices"][0]["message"]
        return message["content"].to_s if message.is_a?(Hash)
      end

      ""
    end


    def self.extract_error_message(response_body, fallback_text)
      if response_body.is_a?(Hash)
        if response_body["error"].is_a?(Hash) && response_body["error"]["message"]
          return response_body["error"]["message"].to_s
        end
        return response_body["message"].to_s if response_body["message"].to_s.strip != ""
      end

      fallback_text.to_s
    end


    def self.extract_generated_code(response_body)
      text = extract_response_text(response_body).to_s.strip

      if text.include?("```")
        fenced = text[/```(?:ruby)?\s*(.*?)```/m, 1]
        text = fenced.to_s.strip if fenced
      end

      text.gsub!(/\A<pre>\s*/m, "")
      text.gsub!(/\s*<\/pre>\z/m, "")
      text.strip
    end


    def self.ensure_generated_code_is_safe!(generated_code)
      code = generated_code.to_s
      raise "AI response did not contain Ruby code." if code.strip == ""

      forbidden_patterns = {
        /`/ => "shell execution",
        /%x\s*\(/ => "shell execution",
        /\b(system|exec|spawn|fork)\b/ => "process execution",
        /\b(require|load|autoload)\b/ => "dynamic loading",
        /\b(eval|instance_eval|class_eval|module_eval)\b/ => "dynamic evaluation",
        /\b(File|Dir|IO|FileUtils|Tempfile|Open3|Process|ENV|Socket|TCPSocket|UDPSocket|Net::HTTP|OpenURI|Win32|Fiddle|DL)\b/ => "external file, process, or network access",
        /\b(UI\.openURL|UI\.openpanel|UI\.savepanel|UI\.select_directory)\b/ => "external UI or file access",
        /\b(Sketchup\.find_support_file|Sketchup\.require|Sketchup\.load)\b/ => "external file loading",
        /^\s*(class|module)\b/ => "class or module definitions",
        /\b(Thread|sleep|exit|abort|at_exit)\b/ => "runtime control outside SketchUp"
      }

      forbidden_patterns.each do |pattern, reason|
        if code.match(pattern)
          raise "Blocked generated code: #{reason} is not allowed in execution mode."
        end
      end
    end


    def self.execute_generated_code(generated_code)
      ensure_generated_code_is_safe!(generated_code)

      model = Sketchup.active_model
      previous_stdout = $stdout
      operation_open = false
      result = nil

      begin
        model.start_operation("AI Explorer", true)
        operation_open = true

        $stdout = StringIO.new
        result = eval(generated_code, TOPLEVEL_BINDING, "ai_explorer_generated.rb")
        output = $stdout.string.to_s
        output = result.inspect if output.strip == "" && !result.nil?

        model.commit_operation
        operation_open = false
        output.to_s
      rescue Exception
        model.abort_operation if operation_open && model.respond_to?(:abort_operation)
        raise
      ensure
        $stdout = previous_stdout
      end
    end


    def self.build_dialog(title, width, height)
      dlg = UI::WebDialog.new(title, true, title.gsub(/\s+/, "_"), width, height, 100, 100, true)
      dlg.navigation_buttons_enabled = false if dlg.respond_to?(:navigation_buttons_enabled=)
      dlg
    end


    def self.register_dialog_close(dialog)
      closer = proc { @active_dialog = nil; @dialog = nil }

      if dialog.respond_to?(:set_on_close)
        dialog.set_on_close(&closer)
      elsif dialog.respond_to?(:set_on_closed)
        dialog.set_on_closed(&closer)
      elsif dialog.respond_to?(:on_closed)
        dialog.on_closed(&closer)
      end
    end
    
    
    def self.encoded_screenshot
    # Saves and encodes the current model view in Base64 format
    
        # Save the current model view to a temp location
        dir = (defined? Sketchup.temp_dir) ? Sketchup.temp_dir : ENV['TMPDIR'] || ENV['TMP'] || ENV['TEMP']
        file_loc = File.join( dir, "temp.png" )
        keys = {
            :filename => file_loc,
            :antialias => true,
            :scale_factor => 1,
            :compression => 0.8,
            :transparent => false
        }
        img = Sketchup.active_model.active_view.write_image keys
        
        # Encode the file as Base64
        base64_image = File.open(file_loc, "rb") do |file|
            Base64.strict_encode64(file.read)
        end
        
        return base64_image
    
    end # encoded_screenshot    
    
    
    # ==================        


    def self.encoded_file(file_path)
    # Encodes a file in Base64 format
        
        # Encode the file as Base64
        base64_file = File.open(file_path, "rb") do |file|
            Base64.strict_encode64(file.read)
        end
        
        return base64_file
    
    end # encoded_file    
    
    
    # ==================            
    
    
    def self.show_disclaimer_window
    # Shows a license and disclaimer window
        
        # Show a window with my terms of use
        f = File.join( __dir__ , "license.txt" )
        disclaimer = File.read(f)
        title = @exttitle + " | Readme & Terms of Use"

        dlg = build_dialog(title, 640, 720)
        dlg.set_file(license_file_path)

        dlg.add_action_callback("license_accepted") do |*args|
          Sketchup.write_default( @extname , "disclaimer_acknowledged" , "yes" )
          dlg.close
          self.openai_explorer_dialog
        end  
        
        dlg.add_action_callback("load_license") do |*args|
          js = "applyLicense(#{disclaimer.dump});"
          dlg.execute_script(js)   
        end     
        
        dlg.show
        dlg.center if dlg.respond_to?(:center)

    end # show_disclaimer_window


    # ================== 

    
    def self.openai_explorer_dialog
    # Opens the SketchUp 2016 WebDialog, sends requests to the local proxy, and executes returned Ruby
    
        toolname = @exttitle
        
        # If another dialog from this extension is already open, bring it to front
        if @active_dialog
          begin
            @active_dialog.show
            @active_dialog.center if @active_dialog.respond_to?(:center)
          rescue Exception
          end
          return
        end

        # Show disclaimer once
        default = Sketchup.read_default( @extname , "disclaimer_acknowledged" )        
        if default.to_s != "yes" then 
            self.show_disclaimer_window 
            return
        end       
        
        # Get the settings, including the API key
        settings = read_settings_hash

        # Set up the dialog
        @dialog = build_dialog(toolname, 560, 760)
        @dialog.set_file(dialog_file_path)
        @dialog.show
        @dialog.center if @dialog.respond_to?(:center)

        # Mark this as the active dialog and clear it on close
        @active_dialog = @dialog
        register_dialog_close(@dialog)
        
        # Callback to close dialog
        @dialog.add_action_callback("close_dlg") { |action_context, payload|
          persist_settings(parse_dialog_json(payload))
          @dialog.close
          @active_dialog = nil
          @dialog = nil
        }
        
        # Callback to show disclaimer dialog
        @dialog.add_action_callback("disclaimer_dlg") { |action_context|
            self.show_disclaimer_window
        }  
        
        # Callback to show help dialog
        @dialog.add_action_callback("help_dlg") { |action_context|
            self.show_help
        }

        # Callback to clear dialog
        @dialog.add_action_callback("clear_dlg") { |action_context|
            @ai_messages.clear
            @dialog.execute_script("clearTranscript(); setStatus('Ready.');")
        }             
        
        # Callback to send settings to dialog
        @dialog.add_action_callback("read_settings") { |action_context|
            # Get the current settings
            settings = read_settings_hash
            js = "applySettings(#{settings.to_json}); setStatus('Ready.');"
            @dialog.execute_script(js)                  
        }      

        # Callback to save settings from dialog
        @dialog.add_action_callback("write_settings") { |action_context,payload|
            persist_settings(parse_dialog_json(payload))
        }        
        
        # Callback to submit prompt and get response
        @dialog.add_action_callback("submit_prompt") { |action_context,payload|

          t1 = Time.now
          ruby_result = ''
          generated_code = nil
          response_body = nil
          info = ""
          errmsg = nil

            begin
                request_hash = parse_dialog_json(payload)
                prompt = request_hash["prompt"].to_s.strip
                raise "Prompt is empty." if prompt == ""

                settings = persist_settings(request_hash["settings"].is_a?(Hash) ? request_hash["settings"] : {})
                user_message = { "role" => "user", "content" => prompt }
                history = @ai_messages.last(settings["numPrompts"].to_i)

                # Life is always better with some feedback while SketchUp works
                Sketchup.status_text = toolname + " | Collecting scene context"
                @dialog.execute_script("appendPrompt(#{prompt.dump}); setStatus('Collecting scene context...', true);")

                # Set the local proxy endpoint
                endpoint_str = settings["aiEndpoint"].to_s
                unless endpoint_str.start_with?('http://') || endpoint_str.start_with?('https://')
                  raise "Proxy endpoint must start with http:// or https://, for example http://127.0.0.1:5000/sketchup"
                end
                endpoint = endpoint_str

                # Add raw data to console output
                puts_if_enabled "\n#{@exttitle} - RAW OUTPUT:\n"
                puts_if_enabled "\nPrompt ============\n(System:) #{system_prompt_for(settings)}\n(User:) #{prompt}"

                # Set up the HTTP request to the local proxy
                uri = URI(endpoint)
                req = Net::HTTP::Post.new(uri)
                req["Content-Type"] = "application/json"

                body_hash = build_proxy_request(settings, prompt, history)
                req.body = JSON.dump(body_hash)

                Sketchup.status_text = toolname + " | Sending request to proxy"
                @dialog.execute_script("setStatus('Waiting for local proxy response...', true);")

                # Make the HTTP request to the local proxy and parse the response
                res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https'), open_timeout: 15, read_timeout: 120) do |http|
                  http.request(req)
                end
                begin
                  response_body = JSON.parse(res.body)
                rescue JSON::ParserError
                  response_body = { "content" => res.body.to_s }
                end

                if res.code.to_i >= 400
                  raise extract_error_message(response_body, res.body)
                end
                
                # Add raw response to console output
                puts_if_enabled "\nRaw Request ============\n"
                puts_if_enabled req.body
                puts_if_enabled "\nRaw Response ============\n"
                puts_if_enabled response_body

                generated_code = extract_generated_code(response_body)
                raise "Proxy response did not contain Ruby code." if generated_code == ""

                @ai_messages.push(user_message)
                @ai_messages.push({ "role" => "assistant", "content" => generated_code })

                puts_if_enabled "\nResult ============\n"
                puts_if_enabled generated_code

                # Display some statistics in the Ruby console
                if response_body.is_a?(Hash) && response_body["usage"].is_a?(Hash) && response_body["usage"]["total_tokens"]
                  info += "Tokens used: " + response_body["usage"]["total_tokens"].to_s
                else
                  info += "Tokens used: unknown"
                end
                puts_if_enabled "\nStats ============\n"
                puts_if_enabled info    
                if response_body.is_a?(Hash) && response_body["choices"].is_a?(Array) && response_body["choices"][0].is_a?(Hash)
                  puts_if_enabled "Finish reason: " + response_body["choices"][0]["finish_reason"].to_s
                end

                # Execute code immediately in this test build
                Sketchup.status_text = toolname + " | Executing code"
                @dialog.execute_script("setStatus('Executing Ruby inside SketchUp...', true);")
                ruby_result = execute_generated_code(generated_code)
                info += " | Code was executed."

                # Life is always better with some feedback while SketchUp works
                Sketchup.status_text = toolname + " | Done"     

              rescue Exception => e    
              
                errmsg = e.message.to_s

                puts_if_enabled "This request generated an error. See dialog for details.\n"        

            end    
            
            # Measure duration
            duration = Time.now - t1
            info += " | Time elapsed: %0.2fs" % duration     

            if generated_code && generated_code != ""
              @dialog.execute_script("appendResponse(#{generated_code.dump}, #{info.dump}, #{ruby_result.to_s.dump});")
            end

            if errmsg && errmsg != ""
              @dialog.execute_script("appendError(#{errmsg.dump}, #{info.dump});")
            end

            @dialog.execute_script("setStatus('Ready.');")


        }  # END add_action_callback("submit_prompt") 
    
    end # openai_explorer_dialog    


    # ==================
    
    
    def self.show_url( title , url )
    # Show website in a SketchUp 2016 WebDialog

      @dlg = UI::WebDialog.new( title , true ,
        title.gsub(/\s+/, "_") , 1000 , 600 , 100 , 100 , true)
      @dlg.navigation_buttons_enabled = false if @dlg.respond_to?(:navigation_buttons_enabled=)
      @dlg.set_url( url )
      @dlg.show
    
    end      
    

    # ==================   
    
    
    def self.show_help
    # Show the Help website as an About dialog
    
      show_url( "#{@exttitle} - Help" , 'https://alexschreyer.net/projects/openai-explorer-experimental/' )

    end # show_help    
    
    
    # ==================     
    

    def self.show_openai_api
    # Open the OpenAI settings pages that have the API Keys
    # Need it this way for initial open

      UI.openURL('https://platform.openai.com/api-keys')

    end # show_openai_api   


    # ==================       


    def self.reset_settings
    # Resets all extension settings to their defaults
    
      q = "Do you want to reset all of the extension settings to their defaults? This is mainly for troubleshooting purposes."
      if UI.messagebox( q , MB_YESNO ) == 6

        Sketchup.write_default( @extname , "openai_warning" , nil )
        Sketchup.write_default( @extname , "openai_explorer_settings" , nil )
        Sketchup.write_default( @extname , "openai_explorer" , nil )
        Sketchup.write_default( @extname , "ai_explorer_settings_hash" , nil )
        Sketchup.write_default( @extname , "disclaimer_acknowledged" , nil )

        q = "All settings have been reset."
        UI.messagebox( q , MB_OK )
      
      end

    end # reset_settings      

      
    # ==================          


    load_system_messages


    if !file_loaded?(__FILE__)

      # Add to the SketchUp Extensions menu
      menu = UI.menu("Plugins").add_submenu( @exttitle )
      menu.add_item("AI Explorer Dialog") { self.openai_explorer_dialog }
      menu.add_separator       
      menu.add_item("Get OpenAI API Key") { UI.openURL('https://platform.openai.com/api-keys') }      
      menu.add_item("Check OpenAI API Usage") { UI.openURL('https://platform.openai.com/usage') }
      menu.add_separator 
      menu.add_item("Get Google API Key") { UI.openURL('https://aistudio.google.com/apikey') }  
      menu.add_item("Check Google API Usage") { UI.openURL('https://aistudio.google.com/usage') }
      menu.add_item("Google API Compatibility") { UI.openURL('https://ai.google.dev/gemini-api/docs/openai#rest') }       
      menu.add_separator       
      menu.add_item("Get Anthropic API Key") { UI.openURL('https://console.anthropic.com/settings/keys') }  
      menu.add_item("Check Anthropic API Usage") { UI.openURL('https://console.anthropic.com/usage') }      
      menu.add_item("Anthropic API Compatibility") { UI.openURL('https://docs.anthropic.com/en/api/openai-sdk') }       
      menu.add_separator       
      menu.add_item("Help") { self.show_help }      
      menu.add_item("Terms of Use") { self.show_disclaimer_window }
      menu.add_item("View/edit default system messages") { UI.openURL("file:///#{File.join( @extdir , @extname , "system_msgs.json" )}") }  
      menu.add_item("Reset extension settings") { self.reset_settings }

      # Let Ruby know we have loaded this file
      file_loaded(__FILE__)

    end # if


    # ==================


  end # module AS_OpenAIExplorer2016

end # module AS_Extensions


# ==================
