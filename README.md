# AiFailoverAdapter

This gem is used to connect to multiple instances of a database for always on availability.
Once configured with a list of database hosts or URL's, the adapter will connect to all
databases, and seamlessly switch connections in the event of failure.


The adapter assumes that you have setup a peer-to-peer replication database, and makes
no attempt to assign one database as a master. It will only ever use one connection at
a time for all read and writes, and only switch in the event of failure. 

If a connection fails, it will be given a period of time before it is retried. Once this
time expires, a reconnection will be attempted. If it succeeds, then it will become the
active connection once again. If not, it will be ignored for another period of time.


## Installation

Add this line to your application's Gemfile:

    gem 'ai_failover_adapter'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install ai_failover_adapter

## Usage

To use this gem, you need to reconfigure your database.yml file to use the `ai_failover_adapter`
instead of the default adapter. Below is two examples of possible configurations

    development:
      adapter: ai_failover
      encoding: unicode
      node_adapter: mssql
      pool: 50
      urls:
        - 'jdbc:sqlserver://server1;user=username;password=password;databaseName=rts_dev'
        - 'jdbc:sqlserver://server2;user=username;password=password;databaseName=rts_dev'

    development:
      adapter: ai_failover
      encoding: unicode
      database: rts_dev
      username: username
      password: password
      node_adapter: mssql
      pool: 50
      hosts:
        - server1
        - server2

The above configurations show how you can specify either the URL's of each server, or just the
hosts. The rest of the configuration is shared between each of the servers. If you need to use
different configurations per server, then you should use the URL's option, as most options can 
be supplied via the URL parameters. Otherwise, simply put all configuration options in the same
place as usual, and they will be used for each connection.


##Contribution

The code is developed and maintained by [The ai Corporation](https://github.com/thoughtified)  (originally created by  [@pareeohnos](https://github.com/pareeohnos))