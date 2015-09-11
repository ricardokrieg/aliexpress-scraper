String::startsWith ?= (s) -> @[...s.length] is s
String::endsWith   ?= (s) -> s is '' or @[-s.length..] is s

String::toCurrency  ?= -> parseFloat(parseFloat(@.replace(/[^\d\.,]/g, '').replace(/,/g, '.')).toFixed(2))
String::strip ?= -> @.replace(/\s\s+/g, ' ').replace(/^\s+|\s+$/g, '')
