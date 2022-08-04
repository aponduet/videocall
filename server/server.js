const express = require('express');
const cors = require('cors');
const app = express();
const http = require('http');
const server = http.createServer(app);
const io = require("socket.io")(server);

require('dotenv').config();
//const port = process.env.PORT || 3000;
const port = 3000;
app.use(express.json());
app.use(cors());

app.get('/', (req, res) => {
    res.send( 'Hello Sohel');
  });


io.on("connection",  (socket)=> {
     console.log("New client connected");
      //console.log(io.sockets.adapter.rooms);
      //console.log(io);
    //  console.log(socket.id);

    socket.on("join", (roomId) => {
        socket.join(roomId);
    });

    

    socket.on("newConnect", (roomId, callback) => {
        
        //console.log(callback);
        //console.log(io.sockets.adapter.rooms);
        let socketIds = Object.keys(io.sockets.adapter.rooms[roomId].sockets).filter(id => id !== socket.id);
        // console.log(socketIds);
        // console.log(socket.id);
        callback({ originId: socket.id, destinationIds: socketIds });
    })

    socket.on("createOffer", (data) => {
        console.log(data);
        var socketId = {
            originId: data.socketId.destinationId,
            destinationId: data.socketId.originId
        }
        //console.log(session);
        io.to(data.socketId.destinationId).emit("receiveOffer", { session: data.session, socketId: socketId });
        //socket.broadcast.emit("receiveOffer", { session: data.session, socketId: socketId });
    })

    socket.on("createAnswer", (data) => {
        console.log("createAnswer event is called.");
        var socketId = { 
            originId: data.socketId.destinationId,
            destinationId: data.socketId.originId
        }
        io.to(data.socketId.destinationId).emit("receiveAnswer", { session: data.session, socketId: socketId });
    })

    socket.on("sendCandidate", (data) => {
        console.log("sendCandidate event is called.");
        var socketId = {
            originId: data.socketId.destinationId,
            destinationId: data.socketId.originId
        }
        //console.log(data);
        io.to(data.socketId.destinationId).emit("receiveCandidate", { candidate: data.candidate, socketId: socketId });
    })
    socket.on("disconnect", () => {
        console.log("Disconnect event is called.");
        socket.broadcast.emit("userDisconnected", socket.id);
        //console.log("Client disconnected", socket.id);
    })
})

server.listen(port, () => console.log(`Server Listening on port ${port}`));