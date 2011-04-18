Infer
====================
I often found myself spending way too much time perusing directories to find a file I knew existed, but was uncertain of its exact path. I also hated making the decision to leave my working directory at the root of a project to a nested directory just because I expect to be running enough commands on the files within saving me the repetition of prefixing the paths.

Infer is a command line utility that makes it easy to immediately open a file for editing when you have prior knowledge of the path name.

Design Goals
====================
* Do not reinvent the wheel; leverage the often unutilized power of grep and mdfind for the hard stuff.
* Minimize keystrokes for the most common usecases, but not at the cost of unixisms. 

Example
====================

<pre>
$ infer user
Searching ./

Ambiguous:

0. |||||||||| ./app/views/admin/users/_users.html.erb 
1. |||||||||| ./app/models/user.rb 
2. |||||||||  ./app/views/admin/users
3. |||||||||  ./test/unit/user_test.rb 
4. ||||||||   ./spec/factories/users.rb 
5. ||||||||   ./test/fixtures/users.yml 
6. ||||||||   ./app/views/company/users 
7. ||||||||   ./app/models/user_login.rb 
8. ||||||||   ./spec/models/user_spec.rb 
9. ||||||||   ./app/models/user_invite.rb 

81 more hidden.

Try refining the search,
or pick one of the above (0-9):
</pre>

The highest match for keyword "user" is less than the inference index (10%). Now you know this, and can add an distinguishing keyword to the search now and in the future:

<pre>
$ infer user model
</pre>
Opens ./app/models/user.rb because its rank is greater than the proceeding by more the defined inference index.
How it is opened is defined by "matchers" and "handlers" that can be defined in ~/.infer.yml. By default everything opens with vim.


Configuration
====================
Example ~/.infer.yml
<pre>
inference_index: 0.1  # Open if first result is 10% better than the next

# Regexes used to classify files by name
matchers:
  scalar_graphics: "\\.(psg|png|jpeg|jpg|gif|tiff)$"
  vector_graphics: "\\.(ai|eps)$"

# Commands that get executed on an inference, $ holds the full file name
handlers:
  scalar_graphics: "open -a \"Adobe Photoshop CS5\" $"
  vector_graphics: "open -a \"Adobe Illustrator CS5\" $"
  default: "vim $"  # Catch-all if nothing else is matched (make this your most general-purpose editor, e.g. mate)
</pre>

Installation
====================
Simply make infer executable from the path and have ruby installed. It has no dependencies outside of the ruby standard library. Note: I've only tested with ruby 1.9.


Why mdfind is rad
====================
The HFS+ filesystem is built around the central metastore keeping in constant sync.


Todo
====================
* Make it possible to use mdfind and locate instead of recursing directories. Will give you the ability to opt for speed over integrity in really large projects.
* Integration with vim, e.g. popping open an inference in a split.
* Store results in the parent shell environment variables for quick subsequent commands on the results? Debating this.
* Interactive mode
* More options

Notes
====================
It is *surprisingly* fast and yields good real-world results from the feedback I've received, despite it being a pretty simple approach.
