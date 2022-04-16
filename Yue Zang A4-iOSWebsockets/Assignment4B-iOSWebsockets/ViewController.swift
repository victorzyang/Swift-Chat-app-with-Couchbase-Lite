//
//  ViewController.swift
//  Assignment4B-iOSWebsockets
//
//  Created by Yue Zhang Winter 2018
//  Modified for 2601 Winter 2019 by Louis D. Nel
//  Copyright © 2018 COMP2601. All rights reserved.
//
/*
 For testing:
 The application will read a URL address e.g.
 http://localhost:3000 or
 http://134.117.26.92:3000
 from the user input text field and connect to that server.
 If none is supplied then the localhost address will be used.
 */
import UIKit
import Starscream
import PopupDialog
import CouchbaseLiteSwift //added for thesis

class ViewController: UIViewController, UITableViewDataSource, WebSocketDelegate {
    
    enum ConnectionType {
        case Connect
        case Disconnet
    }
    
    // MARK: Properties
    
    @IBOutlet var userInput: UITextField!
    @IBOutlet var connectButton: UIButton!
    @IBOutlet var disconnectButton: UIButton!
    @IBOutlet var sendMessageButton: UIButton!
    @IBOutlet var messageTableView: UITableView!
    
    var socket: WebSocket!
    var messages: [String] = []
    var request = URLRequest(url: URL(string: "http://localhost:3000")!)
    //var request = URLRequest(url: URL(string: "http://134.117.26.92:3000")!)
    
    //added for thesis
    var database:Database? = nil
    var listOfMessages: [String] = []
    var listOfDateTimes: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
 
        do {
            database = try Database(name: "chatHistoryDB")
        } catch {
            fatalError("Error opening database")
        }
        
        request.timeoutInterval = 30
        socket = WebSocket(request: request)
        socket.delegate = self
        disconnectButton.isEnabled = false
        sendMessageButton.isEnabled = false
        messageTableView.dataSource = self
        userInput.text = "http://localhost:3000"
    }
    
    // MARK: Websocket Delegate Methods
    
    func websocketDidConnect(socket: WebSocketClient) {
        print("websocketDidConnect")
        showDialog(type: ConnectionType.Connect)
        toggleButtons()
    }
    
    //when user disconnects, the chat history up until the user disconnection is inserted into database
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        print("websocketDidDisconnect")
        if let e = error as? WSError {
            showDialog(type: ConnectionType.Disconnet, message: e.message)
        } else if let e = error {
            showDialog(type: ConnectionType.Disconnet, message: e.localizedDescription)
        } else {
            showDialog(type: ConnectionType.Disconnet)
        }
        
        let mutableDoc = MutableDocument(); //document representing an array of messages during a certain period
        let messagesArray = MutableArrayObject()
        
        //iterate through all messages up until a user disconnection
        for m in 0..<listOfMessages.count {
            let messageDict = MutableDictionaryObject();
            messageDict.setString("User", forKey: "User")
            messageDict.setString(listOfMessages[m], forKey: "Message")
            messageDict.setString(listOfDateTimes[m], forKey: "Datetime")
            messagesArray.addDictionary(messageDict)
        }
        
        //set the attributes of the document
        mutableDoc.setString("messages", forKey: "type")
        mutableDoc.setArray(messagesArray, forKey: "Messages")

        do {
            try database?.saveDocument(mutableDoc) //save document to database
        } catch {
            fatalError("Error saving document")
        }
        
        //reset the helper lists
        listOfMessages.removeAll() //added for thesis
        listOfDateTimes.removeAll() //added for thesis
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        if ( !text.contains("Connected to Server") ) {
            messages.append(text)
            updateTableView()
            
            listOfMessages.append(text) //add message to helper list of messages
            
            //Get the date of the message (ie. the current date)
            let date = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd/MM/yyyy"
            let datetime = dateFormatter.string(from: date)
            listOfDateTimes.append(datetime) //add date to helper list of datetimes
            
        }
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        print("Received data: \(data.count)")
    }
    
    // MARK: Write Text Action
    
    @IBAction func writeText(_ sender: UIButton) {
        if (userInput.text != nil && userInput.text != "") {
            socket.write(string: userInput.text!)
            userInput.text = ""
        }
    }
    
    // MARK: Connect/Disconnent Action
    
    @IBAction func connect(_ sender: UIButton) {
        if (!socket.isConnected) {
            //read chat client server address from user text field
            if (userInput.text != nil && userInput.text != "") {
                let addressString = userInput.text!.trimmingCharacters(in: .whitespacesAndNewlines)
                print("URL address string: \(addressString)" )
                let url = URL(string: addressString)!
                print("url.host: \(url.host!)")
                print("url.port: \(url.port!)")
                request = URLRequest(url: URL(string: addressString)!)
                request.timeoutInterval = 120
                socket.request = request
            }
            socket.connect()
        }
    }
    
    @IBAction func disconnect(_ sender: UIButton) {
        if socket.isConnected {
            socket.disconnect()
            toggleButtons()
        }
    }
    
    // Display database data
    @IBAction func displayData(_ sender: UIButton){
        //query to fetch documents of type "messages"
        let resultSet = QueryBuilder
            .select(
                SelectResult.expression(Meta.id),
                SelectResult.property("Messages"))
            .from(DataSource.database(database!))
            .where(Expression.property("type").equalTo(Expression.string("messages")))
        
        var messageDisplay = "" //this is the variable containing everything to display to the UI
        
        //run the 'resultSet' query
        do {
            for result in try resultSet.execute() { //iterates through all messages in all chat sessions in the database to append information to display to the messageDisplay variable
                messageDisplay += "Messages: ["
                let messagesArray = result.array(forKey: "Messages")
                for index in 0..<messagesArray!.count{
                    messageDisplay += "{Message_id: "
                    messageDisplay += result.string(forKey: "id")!
                    messageDisplay += ", User: "
                    messageDisplay += (messagesArray?.dictionary(at: index)?.string(forKey: "User"))!
                    messageDisplay += ", Message: "
                    messageDisplay += (messagesArray?.dictionary(at: index)?.string(forKey: "Message"))!
                    messageDisplay += ", Datetime: "
                    messageDisplay += (messagesArray?.dictionary(at: index)?.string(forKey: "Datetime"))!
                    if index != messagesArray!.count - 1 {
                        messageDisplay += "}, "
                    } else {
                        messageDisplay += "}"
                    }
                }
                
                messageDisplay += "]\n\n"
            }
            
            showMessage(title: "Database Data", message: messageDisplay) //calls function to trigger an alert that displays the database data
        } catch {
            print(error)
        }
    }
    
    //function for which an alert pops up to display database data
    func showMessage(title: String, message: String){
        let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { action in
            switch action.style{
                case .default:
                print("default")
                
                case .cancel:
                print("cancel")
                
                case .destructive:
                print("destructive")
                
            }
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    // MARK: TableView Methods
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell")!
        
        let text = messages[indexPath.row]
        
        cell.textLabel?.text = text
        
        return cell
    }
    
    // MARK: Private method
    
    private func toggleButtons() {
        connectButton.isEnabled = !connectButton.isEnabled
        disconnectButton.isEnabled = !disconnectButton.isEnabled
        sendMessageButton.isEnabled = disconnectButton.isEnabled
    }
    
    private func updateTableView() {
        messageTableView.beginUpdates()
        messageTableView.insertRows(at: [IndexPath(row: messages.count-1, section: 0)], with: .automatic)
        messageTableView.endUpdates()
    }
    
    // MARK: Dialog Methods
    func showDialog(type: ConnectionType, message: String? = nil, animated: Bool = true) {
        var title: String!
        // Prepare the popup
        if (type == ConnectionType.Connect){
            title = "Connected to Server"
        }
        else {
            title = "Disconnect from Server"
        }
        
        // Create the dialog
        let popup = PopupDialog(title: title,
                                message: message,
                                buttonAlignment: .horizontal,
                                transitionStyle: .zoomIn,
                                tapGestureDismissal: true,
                                hideStatusBar: true) {
                                    print("Completed")
        }
        
        // Create first button
        let buttonOne = DefaultButton(title: "OK"){}
        
        // Add buttons to dialog
        popup.addButtons([buttonOne])
        
        // Present dialog
        self.present(popup, animated: animated, completion: nil)
    }
    
}
