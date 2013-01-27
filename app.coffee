fs = require 'fs'
request = require 'request'
$ = require 'jQuery'
restler = require 'restler'

#redis = require 'redis'
#rclient = redis.createClient()

express = require 'express'
app = express()
http = require 'http'
httpserver = http.createServer(app)
httpserver.listen(3333)
nowjs = require 'now'
everyone = nowjs.initialize(httpserver)

app.configure('development', () ->
  app.use(express.errorHandler())
)

app.configure( ->
  app.set('views', __dirname + '/views')
  app.set('view engine', 'ejs')
  app.use(express.bodyParser())
  app.use(express.methodOverride())
  app.set('view options', { layout: false })
  app.locals({ layout: false })
  app.use(express.static(__dirname + '/'))
)

fixParticipantFormat = (x) ->
  if x.email?
    return x
  else
    return {'email': x[0], 'fullname': x[1]}

fixEventParticipantFormat = (event) ->
  if not event.participants?
    event.participants = []
  participants = (fixParticipantFormat(participant) for participant in event.participants)
  event.participants = participants
  return event

{cl: classes, ev: allevents} = JSON.parse fs.readFileSync('psetparty.json', 'utf-8')
if not allevents?
  allevents = {}
do ->
  for k,v of allevents
    #console.log allevents[k]
    allevents[k] = (fixEventParticipantFormat(event) for event in allevents[k])
#everyone.now.events = allevents

classlist = []
classlist_set = {}

classdata = fs.readFileSync('classes.txt', 'utf-8')
for line in classdata.split('\n')
  if line.indexOf('\t') == -1
    continue
  subjectnum = line.split('\t')[0]
  if not classlist_set[subjectnum]?
    classlist_set[subjectnum] = true
    classlist.push subjectnum
classlist.sort()

buildingdata = fs.readFileSync('buildings.txt', 'utf-8')
location_list = []
location_addresses = {}
for line in buildingdata.split('\n')
  [buildingname,buildingaddress] = line.split('\t')
  location_list.push buildingname
  location_addresses[buildingname] = buildingaddress

everyone.now.location_list = location_list
everyone.now.location_addresses = location_addresses

getAddress = everyone.now.getAddress = (location) ->
  addr = location_addresses[location]
  if addr?
    return addr + ' , MIT, Cambridge, MA'
  return location + ' , MIT, Cambridge, MA'

everyone.now.addClassType = (classname) ->
  if typeof classname != typeof ''
    return
  if not classlist_set[classname]?
    classlist_set[classname] = true
    classlist.push classname
    classlist.sort()

everyone.now.getClassesWithPrefix = (prefix, callback) ->
  matches = (x for x in classlist when x.indexOf(prefix) == 0)
  callback matches

everyone.now.getCalendarId = getCalendarId = (classname, callback) ->
  restler.get('http://localhost:5000/calid?title=' + classname).on('complete', callback)

root.classids = {}

###
# s: "2013-01-21T07:30:00-05:00"
splitTimeRange = (s) ->
  [date,timerange] = s.split('T')
  [start,end] = timerange.split('-')
  startTime = new Date(date + 'T' + start)
  endTime = new Date(date + 'T' + end)
  return [startTime, endTime]
###

parseEvent = (event) ->
  #[startTime, endTime] = splitTimeRange(event.start.dateTime)
  return {
    'id': event.id,
    'title': event.summary,
    'start': new Date(event.start.dateTime),
    'end': new Date(event.end.dateTime),
  }

getEventsForUser = everyone.now.getEventsForUser = (username, callback) ->
  await
    getClasses(username, defer(classlist))
  events_per_class = []
  await
    for title,i in classlist
      getEvents(title, defer(events_per_class[i]))
  events = []
  for events_for_class in events_per_class
    for event in events_for_class
      events.push event
  callback events

mkId = () -> Math.floor(Math.random()*9007199254740992)

deleteEvent = everyone.now.deleteEvent = (subjectname, eventid, callback) ->
  allevents[subjectname] = (x for x in allevents[subjectname] when x.id != eventid)
  if callback?
    callback()
  everyone.now.refreshUser()

addEvent = everyone.now.addEvent = (subjectname, event, callback) ->
  if not allevents[subjectname]?
    allevents[subjectname] = []
  newid = event.id ? mkId()
  event.id = newid
  event.address = getAddress(event.location)
  event.subjectname = subjectname
  allevents[subjectname].push event
  if callback?
    callback newid
  everyone.now.refreshUser()

toValues = (dict) ->
  output = []
  for key,value of dict
    output.push value
  return output

getEvents = everyone.now.getEvents = (title, callback) ->
  ###
  restler.get('http://localhost:5000/events?title=' + title).on('complete', (events) ->
    items = events.items ? []
    callback (parseEvent(event) for event in items)
  )
  ###
  if not allevents[title]?
    allevents[title] = []
  callback allevents[title]

app.get '/events', (req, res) ->
  title = req.query.title
  if title?
    getEvents(title, (x) -> res.json(x))
    return
  username = req.query.username
  if username?
    getEventsForUser(username, (x) -> res.json(x))
    return
  res.send 'no title or username specified'

app.get '/classes', (req, res) ->
  username = req.query.username
  if username?
    getClasses(username, (x) -> res.json(x))

dumpToDisk = () ->
  ndata = JSON.stringify({cl: classes, ev: allevents})
  fs.writeFileSync('psetparty.json', ndata, 'utf-8')
  return ndata

app.get '/save', (req, res) ->
  res.send dumpToDisk()

everyone.now.getCalendarIds = (classnames, callback) ->
  await
    for title,i in classnames
      if not root.classids[title]?
        getCalendarId(title, defer(classids[title]))
  callback(root.classids)

everyone.now.getClasses = getClasses = (username, callback) ->
  if not classes[username]?
    classes[username] = []
  if callback?
    callback(classes[username])

everyone.now.addClass = (username, classname, callback) ->
  if not classes[username]?
    classes[username] = []
  if classes[username].indexOf(classname) == -1
    classes[username].push classname
  if callback?
    callback(classes[username])

everyone.now.removeClass = (username, classname, callback) ->
  if not classes[username]?
    classes[username] = []
  classes[username] = (x for x in classes[username] when x != classname)
  if callback?
    callback()

addUserIfNotPresent = (event, user) ->
  emails = (x.email for x in event.participants)
  if emails.indexOf(user.email) == -1
    event.participants.push user

removeUserIfPresent = (event, user) ->
  emails = (x.email for x in event.participants)
  if emails.indexOf(user.email) != -1
    newparticipants = (x for x in event.participants when x.email != user.email)
    event.participants = newparticipants

everyone.now.joinEvent = (event, user) ->
  eventid = event.id 
  title = event.subjectname
  if not allevents[title]?
    return
  for i in [0...allevents[title].length]
    if eventid == allevents[title][i].id
      addUserIfNotPresent(allevents[title][i], user)
  everyone.now.refreshUser()

everyone.now.leaveEvent = (event, user) ->
  eventid = event.id
  title = event.subjectname
  if not allevents[title]?
    return
  for i in [0...allevents[title].length]
    if eventid == allevents[title][i].id
      removeUserIfPresent(allevents[title][i], user)
  everyone.now.refreshUser()

process.on 'SIGINT', () ->
  console.log dumpToDisk()
  process.exit()

process.on 'SIGTERM', () ->
  console.log dumpToDisk()
  process.exit()

process.on 'SIGQUIT', () ->
  console.log dumpToDisk()
  process.exit()
