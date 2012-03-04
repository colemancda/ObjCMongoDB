//
//  BSONDocument.m
//  ObjCMongoDB
//
//  Copyright 2012 Paul Melnikow and other contributors
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "BSONIterator.h"

@interface BSONIterator (Private)
@end

@implementation BSONIterator

#pragma mark - Initialization

- (BSONIterator *) initWithDocument:(BSONDocument *)document {
    if (self = [super init]) {
#if __has_feature(objc_arc)
        _document = document;
#else
        _document = [document retain];
#endif
        _b = [document bsonValue];
        _iter = malloc(sizeof(bson_iterator));
        bson_iterator_init(_iter, _b->data);
        _type = bson_iterator_type(_iter);
    }
    return self;
}

// Called internally when creating subiterators
// Takes ownership of the bson_iterator it's passed
- (BSONIterator *) initAsSubIteratorWithDocument:(BSONDocument *)document
                                       iterator:(BSONIterator *)iterator
                                newBsonIterator:(bson_iterator *)bsonIter {
    if (self = [super init]) {
#if __has_feature(objc_arc)
        _document = document;
        self.objectForUndefined = iterator.objectForUndefined;
#else
        _document = [document retain];
#endif
        _iter = bsonIter;
        _type = bson_iterator_type(_iter);
        
    }
    return self;
}

- (void) dealloc {
    free(_iter);
#if !__has_feature(objc_arc)
    [_document release];
#endif
}

#pragma mark - Searching

- (bson_type) nativeValueTypeForKey:(NSString *) key {
    BSONAssertKeyNonNil(key);
    return _type = bson_find(_iter, _b, BSONStringFromNSString(key));
}

- (BOOL) containsValueForKey:(NSString *) key {
    BSONAssertKeyNonNil(key);
    return bson_eoo != [self nativeValueTypeForKey:key];
}

- (id) objectForKey:(NSString *)key {
    [self nativeValueTypeForKey:key];
    return [self objectValue];
}

- (id) valueForKey:(NSString *)key {
    return [self objectForKey:key];
}

#pragma mark - High level iteration

- (id) nextObject {
    [self next];
    return [self objectValue];
}

#pragma mark - Primitives for advancing the iterator and searching

- (BOOL) hasMore { return bson_iterator_more(_iter); }

- (bson_type) next {
    return _type = bson_iterator_next(_iter);
}

#pragma mark - Information about the current key

- (bson_type) nativeValueType { return _type; }
- (BOOL) isSubDocument { return bson_object == _type; }
- (BOOL) isArray { return bson_array == _type; }

- (NSString *) key { return NSStringFromBSONString(bson_iterator_key(_iter)); }

//not implemeneted
//const char * bson_iterator_value( const bson_iterator * i );

#pragma mark - Values for collections

- (BSONIterator *) subIteratorValue {
    bson_iterator *subIter = malloc(sizeof(bson_iterator));
    bson_iterator_subiterator(_iter, subIter);
    BSONIterator *iterator = [[BSONIterator alloc] initAsSubIteratorWithDocument:_document
                                                      iterator:self
                                               newBsonIterator:subIter];
#if __has_feature(objc_arc)
    return iterator;
#else
    return [iterator autorelease];
#endif    
}

- (BSONDocument *) subDocumentValue {
    BSONDocument *document = [[BSONDocument alloc] init];
    bson_iterator_subobject(_iter, [document bsonValue]);
#if __has_feature(objc_arc)
    return document;
#else
    return [document autorelease];
#endif
}

- (NSArray *) arrayValue {
    NSMutableArray *array = [NSMutableArray array];
    BSONIterator *subIterator = [self subIteratorValue];
    while ([subIterator next]) [array addObject:[subIterator objectValue]];
    return [NSArray arrayWithArray:array];
}

- (id) objectValue {
    switch([self nativeValueType]) {
        case bson_eoo:
            return nil;
        case bson_double:
            return [NSNumber numberWithDouble:[self doubleValue]];
        case bson_string:
            return [self stringValue];
        case bson_object:
            return [self subDocumentValue];
        case bson_array:
            return [self subIteratorValue];
        case bson_bindata:
            return [self dataValue];
        case bson_undefined:
            return [BSONIterator objectForUndefinedValue];
        case bson_oid:
            return [self objectIDValue];
        case bson_bool:
            return [NSNumber numberWithBool:[self boolValue]];
        case bson_date:
            return [self dateValue];
        case bson_null:
            return [NSNull null];
        case bson_regex:
            return [self regularExpressionValue];
        case bson_code:
            return [self codeValue];
        case bson_symbol:
            return [self symbolValue];
        case bson_codewscope:
            return [self codeWithScopeValue];
        case bson_int:
            return [NSNumber numberWithInt:[self intValue]];
        case bson_timestamp:
            return [self timestampValue];
        case bson_long:
            return [NSNumber numberWithLongLong:[self int64Value]];
        default:
            return nil;
    }
}

#pragma mark - Values for basic types

- (double) doubleValue { return bson_iterator_double(_iter); }
- (int) intValue { return bson_iterator_int(_iter); }
- (int64_t) int64Value { return bson_iterator_long(_iter); }
- (BOOL) boolValue { return bson_iterator_bool(_iter); }

- (BSONObjectID *) objectIDValue {
    BSONObjectID *objid = [BSONObjectID objectIDWithNativeOID:bson_iterator_oid(_iter)];
    return [objid autorelease];
}

- (NSString *) stringValue { return NSStringFromBSONString(bson_iterator_string(_iter)); }
- (int) stringLength { return bson_iterator_string_len(_iter); }
- (BSONSymbol *) symbolValue { return [BSONSymbol symbol:[self stringValue]]; }

- (BSONCode *) codeValue { return [BSONCode code:NSStringFromBSONString(bson_iterator_code(_iter))]; }
- (BSONCodeWithScope *) codeWithScopeValue {
#if __has_feature(objc_arc)
    BSONDocument *document = [[BSONDocument alloc] init];
#else
    BSONDocument *document = [[[BSONDocument alloc] init] autorelease];
#endif
    bson_iterator_code_scope(_iter, [document bsonValue]);
    return [BSONCodeWithScope code:NSStringFromBSONString(bson_iterator_code(_iter)) withScope:document];
}

- (NSDate *) dateValue {
#if __has_feature(objc_arc)
    return [NSDate dateWithTimeIntervalSince1970:0.001 * bson_iterator_date(_iter)];
#else
    return [[NSDate dateWithTimeIntervalSince1970:0.001 * bson_iterator_date(_iter)] autorelease];
#endif
}

- (char) dataLength { return bson_iterator_bin_len(_iter); }
- (char) dataBinType { return bson_iterator_bin_type(_iter); }
- (NSData *) dataValue {
    id value = [NSData dataWithBytes:bson_iterator_bin_data(_iter)
                          length:[self dataLength]];
#if __has_feature(objc_arc)
    return value;
#else
    return [value autorelease];
#endif
}

- (NSString *) regularExpressionPatternValue { 
    return NSStringFromBSONString(bson_iterator_regex(_iter));
}
- (NSString *) regularExpressionOptionsValue { 
    return NSStringFromBSONString(bson_iterator_regex_opts(_iter));
}
- (BSONRegularExpression *) regularExpressionValue {
    return [BSONRegularExpression regularExpressionWithPattern:[self regularExpressionPatternValue]
                                                       options:[self regularExpressionOptionsValue]];
}

- (BSONTimestamp *) timestampValue {
    return [BSONTimestamp timestampWithNativeTimestamp:bson_iterator_timestamp(_iter)];
}

#pragma mark - Helper methods

+ (id) objectForUndefinedValue {
    static NSString *singleton;
    if (!singleton) singleton = @"bson:undefined";
    return singleton;;
}

@end