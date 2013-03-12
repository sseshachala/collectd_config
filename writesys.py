#!/usr/bin/python

import collectd
import time
try:
  from pymongo import MongoClient as Mongo
except ImportError:
  from pymongo import Connection as Mongo

def read_notif(notif):
  collection = notif.plugin
  parts = notif.message.split("^")
  data = {}
  for p in parts:
    if ": " not in p:
      continue
    k,v = p.split(": ")
    data[k] = v
  data["last_updated"] = time.time()
  customer = data["customer"]
  conn = Mongo()
  dbname = "xervmon_collectd_%s" % (customer, )
  db = conn[dbname]
  info = db[collection]
  info.insert(data)
  conn.close()

collectd.register_notification(read_notif)
