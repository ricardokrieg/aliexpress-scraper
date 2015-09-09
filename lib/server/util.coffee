String::startsWith ?= (s) -> @[...s.length] is s
String::endsWith   ?= (s) -> s is '' or @[-s.length..] is s

String::toCurrency  ?= -> parseFloat(@.replace(/[^\d\.,]/g, '').replace(/,/g, '.'))
String::strip ?= -> @.replace(/\s\s+/g, ' ').replace(/^\s+|\s+$/g, '')
