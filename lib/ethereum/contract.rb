module Ethereum
  class Contract

    attr_accessor :code, :name, :functions, :abi

    def initialize(name, code, abi)
      @name = name
      @code = code
      @abi = abi
      @functions = []
      @abi.select {|x| x["type"] == "function" }.each do |abifun|
        @functions << Ethereum::Function.new(abifun) 
      end
    end

    def build(connection)
      class_name = @name
      functions = @functions
      code = @code
      class_methods = Class.new do

        define_method "connection".to_sym do
          connection
        end

        define_method :deploy do
          deploytx = connection.send_transaction({from: self.sender, gas: 2000000, gasPrice: 60000000000, data: code})["result"]
          self.instance_variable_set("@deployment", Ethereum::Deployment.new(deploytx, connection))
        end

        define_method :deployment do
          self.instance_variable_get("@deployment")
        end

        define_method :deploy_and_wait do |time = 60.seconds|
          self.deploy
          self.deployment.wait_for_deployment(time)
          self.instance_variable_set("@address", self.deployment.contract_address)
        end

        define_method :at do |addr|
          self.instance_variable_set("@address", addr) 
        end

        define_method :address do
          self.instance_variable_get("@address")
        end

        define_method :as do |addr|
          self.instance_variable_set("@sender", addr)
        end

        define_method :sender do
          self.instance_variable_get("@sender") || connection.coinbase["result"]
        end

        define_method :set_gas_price do |gp|
          self.instance_variable_set("@gas_price", gp)
        end

        define_method :gas_price do
          self.instance_variable_get("@gas_price") || 60000000000
        end

        define_method :set_gas do |gas|
          self.instance_variable_set("@gas", gas)
        end

        define_method :gas do 
          self.instance_variable_get("@gas") || 2000000
        end

        functions.each do |fun|
          if fun.constant
            define_method "call_#{fun.name.underscore}".to_sym do |*args|
              formatter = Ethereum::Formatter.new
              arg_types = fun.inputs.collect(&:type)
              #out_types = fun.outputs.collect(&:type)
              connection = self.connection
              return {result: :error, message: "missing parameters for #{fun.function_string}" } if arg_types.length != args.length
              payload = []
              payload << fun.signature
              arg_types.zip(args).each do |arg|
                payload << formatter.to_payload(arg)
              end
              return {result: connection.call({to: self.address, from: self.sender, data: payload.join()})["result"].gsub(/^0x/,'').scan(/.{64}/)}
            end
          else
            define_method "transact_#{fun.name.underscore}".to_sym do |*args|
              formatter = Ethereum::Formatter.new
              arg_types = fun.inputs.collect(&:type)
              connection = self.connection
              return {result: :error, message: "missing parameters for #{fun.function_string}" } if arg_types.length != args.length
              payload = []
              payload << fun.signature
              arg_types.zip(args).each do |arg|
                payload << formatter.to_payload(arg)
              end
              txid = connection.send_transaction({to: self.address, from: self.sender, data: payload.join(), gas: self.gas, gasPrice: self.gas_price})["result"]
              return Ethereum::Transaction.new(txid, self.connection)
            end
            define_method "transact_and_wait_#{fun.name.underscore}".to_sym do |*args|
              function_name = "transact_#{fun.name.underscore}".to_sym
              tx = self.send(function_name, *args)
              tx.wait_for_miner
              return tx
            end
          end
        end
      end
      Object.const_set(class_name, class_methods)
    end

  end
end
