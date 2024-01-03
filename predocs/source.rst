==========
Source
==========

Both Request and Response types provide a constructor named a :code:`source` that takes a function as an
argument, this function should behave similar to luasocket's tcp receive method. To be more specific
the function should take 1 argument, that argument should be either :code:`'*a'`, :code:`'*l'`, or a
number; if omitted it will default to :code:`'*l'`. The return value for this has some additional
constraints, first is that it must return a single line (with new line characters stripped) until
after the trailing new line that signals the last header has been received.

To ease the use of the :code:`source` method the :code:`luncheon.utils` module exposes a few helpers like
the :code:`tcp_socket_source` which works exactly as described above. Either Request or Response parser
will call the source provided with :code:`'*l'` until the end of the headers have been reached.
