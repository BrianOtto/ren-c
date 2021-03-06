REBOL [
    title: "Task worker in REBOL 3"
    author: "Gregg Irwin"
    note: {
        Connects PULL socket to tcp://localhost:5557
        Collects workloads from ventilator via that socket
        Connects PUSH socket to tcp://localhost:5558
        Sends results to sink via that socket
    }
]

import %helpers.r3

to-msec: func [string] [(to integer! string) / 1000]

ctx: zmq-init 1

; Socket to receive messages on
;
receiver: zmq-socket ctx 'pull
zmq-connect receiver tcp://localhost:5557

; Socket to send messages to
;
sender: zmq-socket ctx 'push
zmq-connect sender tcp://localhost:5558

; Process tasks forever
;
forever [
    string: s-recv receiver

    write-stdout unspaced [string "."]  ; simple progress indicator

    wait to-msec string  ; do the work

    s-send sender ""  ; send results to sink
]

zmq-close receiver
zmq-close sender
zmq-term ctx
