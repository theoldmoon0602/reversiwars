import std.socket;
import std.stdio;
import std.json;
import util;

/// User
class User {
private:
	this() {}   /// constructor
public:
	static User[string] users;    /// all user list
	static int[string] actives;   /// active user list
	static int[string] waitings;  /// usernames who waiting for battle 

	string username;   /// username[unique]
	string password;   /// password
	ulong rating;      /// rating
	Connection connection;  /// connection

	/**
	 * Register new user with username and password
     * Throws: Exception on username is not unique or username or password is empty
     */
	static void register(string username, string password) {
		if (username.length == 0 || password.length == 0) {
			throw new Exception("(username > 0) && (password > 0)");
		}
		if (username in users) {
			throw new Exception("username already used");
		}
		auto user = new User();
		user.username = username;
		user.password = password;  // TODO: password encryption
		user.rating = 0;
		user.connection = null;
		users[username] = user;
	}

	/**
     * login by username and password
	 * Throws: Exception on failed to login
     */
	static User login(Connection conn, string username, string password) {
		if (username !in users || users[username].password != password) {
			throw new Exception("login failed");
		}
		if (username in actives) {
			throw new Exception("you already logged in");
		}
		auto user = users[username];
		user.connection = conn;

		actives[username] = 1;   // make user active
		return user;
	}

	void logout() {
		this.connection = null;
		actives.remove(this.username);
	}
}

/// TCP Connection
class Connection {
public:
	Socket socket;  /// Socket

	/// Initializer
	this (Socket socket) {
		this.socket = socket;
	}

	/// called when connection has been started
	void start() {
		writeln("start");
	}

	/// called when connection has been ended
	void close() {
		writeln("end");
	}

	/// called when socket received
	void recv(JSONValue data) {
		writeln("recv: ", data);
	}
}

void main()
{
	import std.stdio;
	import std.string:strip;
	import std.algorithm:each, sort, remove;

	// start tcp socket as server
	auto server = new TcpSocket();
	server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
	server.bind(new InternetAddress(8888));
	server.listen(128);

	Connection[] conns;

	auto rset = new SocketSet();
	auto eset = new SocketSet();

	// listen
	while (true) {
		rset.reset();
		rset.add(server);
		conns.each!((c) => rset.add(c.socket));

		eset.reset();
		eset.add(server);
		conns.each!((c) => eset.add(c.socket));

		Socket.select(rset, null, eset);

		if (eset.isSet(server)) {
			// graceful shutdown
			break;
		}

		if (rset.isSet(server)) {
			auto conn = new Connection(server.accept());
			conn.start();
			conns ~= conn;
		}

		ulong[] rmlist;
		foreach (i, conn; conns) {
			if (eset.isSet(conn.socket)) {
				conn.close();
				rmlist ~= i;
				continue;
			}

			if (rset.isSet(conn.socket)) {
				ubyte[1024] buf;
				auto r = conn.socket.receive(buf);
				if (r == 0 || r == Socket.ERROR) { 
					conn.close();
					rmlist ~= i;
					continue;
				}
				try {
					auto json = parseJSON(buf.asUTF.strip);
					conn.recv(json);
				}
				catch (JSONException) {}
			}

			if (! conn.socket.isAlive) {
				conn.close();
				rmlist ~= i;
			}
		}

		foreach (i; rmlist.sort!"a > b") {
			conns = conns.remove(i);
		}
	}
}
