import QuickRoute.db;
import QuickRoute.jwt;
import QuickRoute.password;
import QuickRoute.time;
import QuickRoute.utils;

import ballerina/data.jsondata;
import ballerina/http;
import ballerina/io;
import ballerina/regex;
import ballerina/sql;
import ballerina/url;
import ballerinax/mysql;
import ballerina/mime;
import QuickRoute.img;

http:ClientConfiguration clientEPConfig = {
    cookieConfig: {
        enabled: true
    }
};
listener http:Listener authEP = new (9091);
listener http:Listener clientEP = new (9092);

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE"],
        allowCredentials: true
    }
}
service /auth on authEP {
    private final mysql:Client connection;

    function init() returns error? {
        self.connection = db:getConnection();
    }

    function __deinit() returns sql:Error? {
        _ = checkpanic self.connection.close();
    }

    resource function post user/register(@http:Payload RequestUser user) returns http:Response|http:Unauthorized|error {
        http:Response response = new;
        json responseObj = {};
        map<string> errorMsg = {};

        boolean errorFlag = false;

        if user.first_name is "" {
            errorFlag = true;
            errorMsg["first_name"] = utils:EMAIL_REQUIRED;
        } else if user.first_name.length() > 45 {
            errorFlag = true;
            errorMsg["first_name"] = utils:FNAME_LENGTH;
        }

        if user.last_name is "" {
            errorFlag = true;
            errorMsg["last_name"] = utils:LNAME_REQUIRED;
        } else if user.last_name.length() > 45 {
            errorFlag = true;
            errorMsg["last_name"] = utils:LNAME_LENGTH;
        }

        if user.email is "" {
            errorFlag = true;
            errorMsg["email"] = utils:EMAIL_REQUIRED;
        } else if user.email.length() > 200 {
            errorFlag = true;
            errorMsg["email"] = utils:EMAIL_LENGTH;
        } else if !regex:matches(user.email, utils:EMAIL_REGEX) {
            errorFlag = true;
            errorMsg["email"] = utils:EMAIL_INVALID_FORMAT;
        }

        if user.password is "" {
            errorFlag = true;
            errorMsg["password"] = utils:PASSWORD_REQUIRED;
        } else if !regex:matches(user.password, utils:PASSWORD_REGEX) {
            errorFlag = true;
            errorMsg["password"] = utils:PASSWORD_LENGTH;
        }

        if errorFlag {
            responseObj = {"success": false, "content": errorMsg.toJson()};
        } else {
            string hashedPassword = password:generateHmac(user.password);
            DBUser|sql:Error result = self.connection->queryRow(`SELECT * FROM user WHERE email = ${user.email}`);
            if result is sql:NoRowsError {
                _ = check self.connection->execute(`INSERT INTO user (first_name,last_name,email,password)  VALUES (${user.first_name}, ${user.last_name}, ${user.email}, ${hashedPassword});`);
                UserDTO UserDTO = {
                    first_name: user.first_name,
                    last_name: user.last_name,
                    email: user.email,
                    userType: "user",
                    expiryTime: time:expierTimeStamp()
                };
                string token = check jwt:generateJWT(UserDTO.toJsonString());
                responseObj = {"success": true, "content": "Successfully Registered", "token": token};
            } else {
                responseObj = {"success": false, "content": "User already exists"};
            }
        }
        response.setJsonPayload(responseObj);
        return response;
    }

    resource function post user/login(@http:Payload LoginUser user) returns http:Response|http:Unauthorized|error {
        http:Response response = new;
        json responseObj = {};
        map<string> errorMsg = {};
        boolean errorFlag = false;

        if user.email is "" {
            errorFlag = true;
            errorMsg["email"] = utils:EMAIL_REQUIRED;
        } else if !regex:matches(user.email, utils:EMAIL_REGEX) {
            errorFlag = true;
            errorMsg["email"] = utils:EMAIL_INVALID_FORMAT;
        }

        if user.password is "" {
            errorFlag = true;
            errorMsg["password"] = utils:PASSWORD_REQUIRED;
        }

        if errorFlag {
            responseObj = {"success": false, "content": errorMsg.toJson()};
        } else {
            DBUser|sql:Error result = self.connection->queryRow(`SELECT * FROM user WHERE email = ${user.email}`);
            if result is DBUser {
                boolean isPasswordValid = password:verifyHmac(user.password, result.password);
                if isPasswordValid {
                    UserDTO UserDTO = {
                        first_name: result.first_name,
                        last_name: result.last_name,
                        email: result.email,
                        userType: "user",
                        expiryTime: time:expierTimeStamp()
                    };
                    string token = check jwt:generateJWT(UserDTO.toJsonString());
                    io:println(token);
                    io:println(url:decode(token, "UTF-8"));
                    responseObj = {"success": true, "content": "Successfully Signed In", "token": token};
                } else {
                    responseObj = {"success": false, "content": "Invalid password"};
                }
            } else {
                responseObj = {"success": false, "content": "User not found"};
            }
        }

        response.setJsonPayload(responseObj);
        return response;
    }

    resource function post admin/login(@http:Payload LoginUser user) returns http:Response|http:Unauthorized|error {
        http:Response response = new;
        json responseObj = {};
        map<string> errorMsg = {};
        boolean errorFlag = false;

        if user.email is "" {
            errorFlag = true;
            errorMsg["email"] = utils:EMAIL_REQUIRED;
        } else if !regex:matches(user.email, utils:EMAIL_REGEX) {
            errorFlag = true;
            errorMsg["email"] = utils:EMAIL_INVALID_FORMAT;
        }

        if user.password is "" {
            errorFlag = true;
            errorMsg["password"] = utils:PASSWORD_REQUIRED;
        }

        if errorFlag {
            responseObj = {"success": false, "content": errorMsg.toJson()};
        } else {
            DBUser|sql:Error result = self.connection->queryRow(`SELECT * FROM admin WHERE email = ${user.email}`);
            if result is DBUser {
                boolean isPasswordValid = password:verifyHmac(user.password, result.password);
                if isPasswordValid {
                    UserDTO UserDTO = {
                        first_name: result.first_name,
                        last_name: result.last_name,
                        email: result.email,
                        userType: "admin",
                        expiryTime: time:expierTimeStamp()
                    };
                    string token = check jwt:generateJWT(UserDTO.toJsonString());
                    responseObj = {"success": true, "content": "Successfully Signed In", "token": token};
                } else {
                    responseObj = {"success": false, "content": "Invalid password"};
                }
            } else {
                responseObj = {"success": false, "content": "User not found"};
            }
        }

        response.setJsonPayload(responseObj);
        return response;
    }

    resource function get user/checkin/[string BALUSERTOKEN]() returns error? {
        json decodeJWT = check jwt:decodeJWT(BALUSERTOKEN);
        UserDTO payload = check jsondata:parseString(decodeJWT.toString());
        if payload.userType is "user" {
            io:println(payload);
        }
    }
}

service /data on clientEP {
    private final mysql:Client connection;

    function init() returns error? {
        self.connection = db:getConnection();
    }

    function __deinit() returns sql:Error? {
        _ = checkpanic self.connection.close();
    }

    resource function post admin/addDestination(http:Request req) returns http:Response|error? {
        mime:Entity[] parts = check req.getBodyParts();
        http:Response response = new;
        json responseObject = {};
        string coutryId = "";
        string title = "";
        string description = "";
        boolean isImageInclude = false;

        string|error contentType = req.getContentType();
        if contentType is string && !contentType.startsWith("multipart/form-data") {
            responseObject = {"success": false, "content": "Unsupported content type. Expected multipart/form-data."};
        } else if parts.length() == 0 {
            responseObject = {"success": false, "content": "Request body is empty"};
        } else {
            foreach mime:Entity part in parts {
                string? dispositionName = part.getContentDisposition().name;
                string|mime:ParserError text = part.getText();
                if dispositionName is "country_id" {
                    if text is string {
                        coutryId = text;
                    } else {
                        responseObject = {"success": false, "content": "Error in retrieving country_id field"};
                    }
                } else if dispositionName is "title" {
                    if text is string {
                        title = text;
                    } else {
                        responseObject = {"success": false, "content": "Error in retrieving title field"};
                    }
                } else if dispositionName is "description" {
                    if text is string {
                        description = text;
                    } else {
                        responseObject = {"success": false, "content": "Error in retrieving description field"};
                        return error("");
                    }
                } else if dispositionName is "file" {
                    string|mime:ParserError contentTypee = part.getContentType();
                    if contentTypee is string {
                        if string:startsWith(contentTypee, "image/") {
                            isImageInclude = true;
                        } else {
                            responseObject = {"success": false, "content": "Invalid or unsupported image file type"};
                        }
                    } else {
                        responseObject = {"success": false, "content": "Failed to retrieve content type"};
                    }
                }
            }

            if coutryId is "" || title is "" || description is "" {
                responseObject = {"success": false, "content": "Parameters are empty"};
            } else {
                if isImageInclude is true {
                    if int:fromString(coutryId) is int {

                        DBCountry|sql:Error result = self.connection->queryRow(`SELECT * FROM country WHERE id=${coutryId}`);
                        if result is sql:NoRowsError {
                            responseObject = {"success": false, "content": "Country not found"};
                        } else if result is sql:Error {
                            responseObject = {"success": false, "content": "Error in retrieving country"};
                        } else {
                            DBDestination|sql:Error desResult = self.connection->queryRow(`SELECT * FROM destinations WHERE title = ${title} AND country_id=${coutryId} `);
                            if desResult is sql:NoRowsError {
                                string|error uploadedImagePath = img:uploadImage(req, "uploads/destinations/", title);
                                if uploadedImagePath is string {
                                    _ = check self.connection->execute(`INSERT INTO destinations (title,country_id,image,description) VALUES (${title},${coutryId},${uploadedImagePath},${description})`);
                                    responseObject = {"success": true, "content": "Successfully uploaded destination"};
                                } else {
                                    responseObject = {"success": false, "content": "Error in uploading image"};
                                }
                            } else if desResult is sql:Error {
                                responseObject = {"success": false, "content": "Error in retrieving destination"};
                            } else {
                                responseObject = {"success": false, "content": "Destination already exists"};
                            }
                        }
                    } else {
                        responseObject = {"success": false, "content": "Invalid type country ID"};
                    }
                } else {
                    responseObject = {"success": false, "content": "Image is required"};
                }
            }
        }

        response.setJsonPayload(responseObject);
        return response;
    }

    resource function post admin/addLocation(http:Request req) returns error|http:Response {
        mime:Entity[] parts = check req.getBodyParts();
        http:Response response = new;
        json responseObject = {};
        string destinationId = "";
        string tourTypeId = "";
        string title = "";
        string overview = "";
        boolean isImageInclude = false;

        string|error contentType = req.getContentType();
        if contentType is string && !contentType.startsWith("multipart/form-data") {
            responseObject = {"success": false, "content": "Unsupported content type. Expected multipart/form-data."};
        } else if parts.length() == 0 {
            responseObject = {"success": false, "content": "Request body is empty"};
        } else {
            foreach mime:Entity part in parts {
                string? dispositionName = part.getContentDisposition().name;
                string|mime:ParserError text = part.getText();
                if dispositionName is "destinationId" {
                    if text is string {
                        destinationId = text;
                    } else {
                        responseObject = {"success": false, "content": "Error in retrieving destinationId field"};
                    }
                } else if dispositionName is "tourTypeId" {
                    if text is string {
                        tourTypeId = text;
                    } else {
                        responseObject = {"success": false, "content": "Error in retrieving tourTypeId field"};
                    }
                } else if dispositionName is "title" {
                    if text is string {
                        title = text;
                    } else {
                        responseObject = {"success": false, "content": "Error in retrieving title field"};
                    }
                } else if dispositionName is "overview" {
                    if text is string {
                        overview = text;
                    } else {
                        responseObject = {"success": false, "content": "Error in retrieving overview field"};
                    }
                } else if dispositionName is "file" {
                    string|mime:ParserError contentTypee = part.getContentType();
                    if contentTypee is string {
                        if string:startsWith(contentTypee, "image/") {
                            isImageInclude = true;
                        } else {
                            responseObject = {"success": false, "content": "Invalid or unsupported image file type"};
                        }
                    } else {
                        responseObject = {"success": false, "content": "Failed to retrieve content type"};
                    }
                }
            }

            if destinationId is "" || title is "" || overview is "" || tourTypeId is "" {
                responseObject = {"success": false, "content": "Parameters are empty"};
            } else {
                if isImageInclude is true {
                    if int:fromString(destinationId) is int && int:fromString(tourTypeId) is int {

                        DBDestination|sql:Error desResult = self.connection->queryRow(`SELECT * FROM destinations WHERE id=${destinationId}`);
                        DBTourType|sql:Error tourResult = self.connection->queryRow(`SELECT * FROM tour_type WHERE id=${tourTypeId}`);
                        if desResult is sql:NoRowsError {
                            responseObject = {"success": false, "content": "Destination not found"};
                        } else if tourResult is sql:NoRowsError {
                            responseObject = {"success": false, "content": "Tour Type not found"};
                        } else if desResult is sql:Error {
                            responseObject = {"success": false, "content": "Error in retrieving destination"};
                        } else if tourResult is sql:Error {
                            responseObject = {"success": false, "content": "Error in retrieving tour type"};
                        } else {
                            DBLocation|sql:Error locationResult = self.connection->queryRow(`SELECT * FROM  destination_location WHERE title=${title} AND destinations_id=${destinationId}`);
                            if locationResult is sql:NoRowsError {
                                string|error uploadedImagePath = img:uploadImage(req, "uploads/locations/", title);
                                if uploadedImagePath is string {
                                    _ = check self.connection->execute(`INSERT INTO destination_location (title,image,overview,tour_type_id,destinations_id) VALUES (${title},${uploadedImagePath},${overview},${tourTypeId},${destinationId})`);
                                    responseObject = {"success": true, "content": "Successfully uploaded destination location"};
                                } else {
                                    responseObject = {"success": false, "content": "Error in uploading image"};
                                }
                            } else if locationResult is sql:Error {
                                responseObject = {"success": false, "content": "Error in retrieving location"};
                            } else {
                                responseObject = {"success": false, "content": "Destination Location already exists"};
                            }
                        }
                    } else {
                        responseObject = {"success": false, "content": "Invalid IDs"};
                    }
                } else {
                    responseObject = {"success": false, "content": "Image is required"};
                }
            }
        }

        response.setJsonPayload(responseObject);
        return response;
    }

}
