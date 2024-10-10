public type Province record {|
    int id;
    string name;
|};

public type DBUser record {|
    int id;
    string first_name;
    string last_name;
    string email;
    string password;
|};

public type UserDTO record {|
    string first_name;
    string last_name;
    string email;
|};

public type RequestUser record {|
    string first_name;
    string last_name;
    string email;
    string password;
|};
