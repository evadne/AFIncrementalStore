// AFIncrementalStore.m
//
// Copyright (c) 2012 Mattt Thompson (http://mattt.me)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFIncrementalStore.h"
#import "AFHTTPClient.h"
#import "ISO8601DateFormatter.h"
#import "RASchedulingKit.h"
#import "NSManagedObject+AFIncrementalStore.h"
#import "NSManagedObjectContext+AFIncrementalStore.h"
#import <objc/runtime.h>

NSString * const AFIncrementalStoreUnimplementedMethodException = @"com.alamofire.incremental-store.exceptions.unimplemented-method";
NSString * const AFIncrementalStoreRelationshipCardinalityException = @"com.alamofire.incremental-store.exceptions.relationship-cardinality";

NSString * const AFIncrementalStoreContextWillFetchRemoteValues = @"AFIncrementalStoreContextWillFetchRemoteValues";
NSString * const AFIncrementalStoreContextWillSaveRemoteValues = @"AFIncrementalStoreContextWillSaveRemoteValues";
NSString * const AFIncrementalStoreContextDidFetchRemoteValues = @"AFIncrementalStoreContextDidFetchRemoteValues";
NSString * const AFIncrementalStoreContextDidSaveRemoteValues = @"AFIncrementalStoreContextDidSaveRemoteValues";
NSString * const AFIncrementalStoreRequestOperationKey = @"AFIncrementalStoreRequestOperation";
NSString * const AFIncrementalStorePersistentStoreRequestKey = @"AFIncrementalStorePersistentStoreRequest";

static NSString * const kAFIncrementalStoreResourceIdentifierAttributeName = @"__af_resourceIdentifier";
static NSString * const kAFIncrementalStoreLastModifiedAttributeName = @"__af_lastModified";

static NSDate * AFLastModifiedDateFromHTTPHeaders(NSDictionary *headers) {
    if ([headers valueForKey:@"Last-Modified"]) {
        static ISO8601DateFormatter * _iso8601DateFormatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            _iso8601DateFormatter = [[ISO8601DateFormatter alloc] init];
        });
        
        return [_iso8601DateFormatter dateFromString:[headers valueForKey:@"last-modified"]];
    }
    
    return nil;
}

#pragma mark -

@interface AFIncrementalStore ()
@property (nonatomic, readonly, strong) NSOperationQueue *operationQueue;
@property (nonatomic, readonly, strong) dispatch_queue_t dispatchQueue;
- (void) beginIgnoringRemoteFetchRequestsInContext:(NSManagedObjectContext *)context;
- (void) endIgnoringRemoteFetchRequestsInContext:(NSManagedObjectContext *)context;
- (BOOL) isIgnoringRemoteFetchRequestsInContext:(NSManagedObjectContext *)context;

@property (nonatomic, readonly, strong) NSManagedObjectModel *backingManagedObjectModel;
@property (nonatomic, readonly, strong) NSManagedObjectContext *backingManagedObjectContext;

@end

@implementation AFIncrementalStore {
@private
    NSCache *_backingObjectIDByObjectID;
    NSMutableDictionary *_registeredObjectIDsByResourceIdentifier;
}
@synthesize HTTPClient = _HTTPClient;
@synthesize backingPersistentStoreCoordinator = _backingPersistentStoreCoordinator;
@synthesize operationQueue = _operationQueue;
@synthesize dispatchQueue = _dispatchQueue;
@synthesize backingManagedObjectModel = _backingManagedObjectModel;
@synthesize backingManagedObjectContext = _backingManagedObjectContext;

- (NSArray *)obtainPermanentIDsForObjects:(NSArray *)array error:(NSError **)error {
    NSMutableArray *mutablePermanentIDs = [NSMutableArray arrayWithCapacity:[array count]];
    for (NSManagedObject *managedObject in array) {
        NSManagedObjectID *managedObjectID = managedObject.objectID;
        if ([managedObjectID isTemporaryID] && managedObject.af_resourceIdentifier) {
            NSManagedObjectID *objectID = [self objectIDForEntity:managedObject.entity withResourceIdentifier:managedObject.af_resourceIdentifier];
            [mutablePermanentIDs addObject:objectID];
        } else {
            [mutablePermanentIDs addObject:managedObjectID];
        }
    }
    
    return mutablePermanentIDs;
}

+ (NSString *)type {
    @throw([NSException exceptionWithName:AFIncrementalStoreUnimplementedMethodException reason:NSLocalizedString(@"Unimplemented method: +type. Must be overridden in a subclass", nil) userInfo:nil]);
}

+ (NSManagedObjectModel *)model {
    @throw([NSException exceptionWithName:AFIncrementalStoreUnimplementedMethodException reason:NSLocalizedString(@"Unimplemented method: +model. Must be overridden in a subclass", nil) userInfo:nil]);
}

- (NSOperationQueue *) operationQueue {

    if (!_operationQueue) {
    
        _operationQueue = [RAOperationQueue new];
        _operationQueue.maxConcurrentOperationCount = 1;
    
    }
    
    return _operationQueue;

}

- (dispatch_queue_t) dispatchQueue {

    if (!_dispatchQueue) {
        
        _dispatchQueue = dispatch_queue_create([NSStringFromClass([self class]) UTF8String], DISPATCH_QUEUE_SERIAL);
    
    }
    
    return _dispatchQueue;

}

- (void)notifyManagedObjectContext:(NSManagedObjectContext *)context
             aboutRequestOperation:(AFHTTPRequestOperation *)operation
                   forFetchRequest:(NSFetchRequest *)fetchRequest
{
    NSString *notificationName = [operation isFinished] ? AFIncrementalStoreContextDidFetchRemoteValues : AFIncrementalStoreContextWillFetchRemoteValues;
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:operation forKey:AFIncrementalStoreRequestOperationKey];
    [userInfo setObject:fetchRequest forKey:AFIncrementalStorePersistentStoreRequestKey];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:context userInfo:userInfo];
        
    });

}

- (void)notifyManagedObjectContext:(NSManagedObjectContext *)context
            aboutRequestOperations:(NSArray *)operations
             forSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest
{
    NSString *notificationName = [[operations lastObject] isFinished] ? AFIncrementalStoreContextDidSaveRemoteValues : AFIncrementalStoreContextWillSaveRemoteValues;
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:operations forKey:AFIncrementalStoreRequestOperationKey];
    [userInfo setObject:saveChangesRequest forKey:AFIncrementalStorePersistentStoreRequestKey];

    [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:context userInfo:userInfo];
}

- (BOOL) loadMetadata:(NSError *__autoreleasing *)error {
    
    if (!_backingObjectIDByObjectID) {
        
        [self setMetadata:@{
            NSStoreTypeKey: [[self class] type],
            NSStoreUUIDKey: [[NSProcessInfo processInfo] globallyUniqueString]
        }];
        
        _backingObjectIDByObjectID = [[NSCache alloc] init];
        _registeredObjectIDsByResourceIdentifier = [[NSMutableDictionary alloc] init];
        
        return YES;
        
    } else {
        
        return NO;
        
    }
    
}

# pragma mark Backing

- (NSManagedObjectModel *) backingManagedObjectModel {

    if (!_backingManagedObjectModel) {
    
        NSManagedObjectModel *model = [self.persistentStoreCoordinator.managedObjectModel copy];
        
        for (NSEntityDescription *entity in model.entities) {
        
            // Don't add properties for sub-entities, as they already exist in the super-entity 
            if ([entity superentity]) {
                continue;
            }
            
            NSAttributeDescription *resourceIdentifierProperty = [[NSAttributeDescription alloc] init];
            [resourceIdentifierProperty setName:kAFIncrementalStoreResourceIdentifierAttributeName];
            [resourceIdentifierProperty setAttributeType:NSStringAttributeType];
            [resourceIdentifierProperty setIndexed:YES];
            
            NSAttributeDescription *lastModifiedProperty = [[NSAttributeDescription alloc] init];
            [lastModifiedProperty setName:kAFIncrementalStoreLastModifiedAttributeName];
            [lastModifiedProperty setAttributeType:NSDateAttributeType];
            [lastModifiedProperty setIndexed:NO];
            
            [entity setProperties:[entity.properties arrayByAddingObjectsFromArray:[NSArray arrayWithObjects:resourceIdentifierProperty, lastModifiedProperty, nil]]];
            
        }
        
        _backingManagedObjectModel = model;
    
    }
    
    return _backingManagedObjectModel;

}

- (NSPersistentStoreCoordinator *) backingPersistentStoreCoordinator {

    if (!_backingPersistentStoreCoordinator) {
    
        _backingPersistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.backingManagedObjectModel];
    
    }
    
    return _backingPersistentStoreCoordinator;

}

- (NSManagedObjectContext *) backingManagedObjectContext {
    
    if (!_backingManagedObjectContext) {
        
        _backingManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        
        _backingManagedObjectContext.persistentStoreCoordinator = _backingPersistentStoreCoordinator;
        _backingManagedObjectContext.retainsRegisteredObjects = YES;
        
    }
    
    return _backingManagedObjectContext;
    
}

- (NSManagedObjectID *)objectIDForEntity:(NSEntityDescription *)entity
                  withResourceIdentifier:(NSString *)resourceIdentifier {
    if (!resourceIdentifier) {
        return nil;
    }
    
    NSManagedObjectID *objectID = _registeredObjectIDsByResourceIdentifier[entity.name][resourceIdentifier];
    
    if (objectID == nil) {
        objectID = [self newObjectIDForEntity:entity referenceObject:resourceIdentifier];
    }
    
    NSCParameterAssert([objectID.entity.name isEqualToString:entity.name]);
    
    return objectID;
}

- (NSFetchRequest *) fetchRequestForObjectIDWithEntity:(NSEntityDescription *)entity resourceIdentifier:(NSString *)resourceID {

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:entity.name];
    fetchRequest.resultType = NSManagedObjectIDResultType;
    fetchRequest.fetchLimit = 1;
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K = %@", kAFIncrementalStoreResourceIdentifierAttributeName, resourceID];

    return fetchRequest;

}

- (NSManagedObjectID *)objectIDForBackingObjectForEntity:(NSEntityDescription *)entity
                                  withResourceIdentifier:(NSString *)resourceIdentifier
{

    NSError *error = nil;
    NSManagedObjectID *objectID = [self backingObjectIDForEntity:entity resourceIdentifier:resourceIdentifier inContext:self.backingManagedObjectContext error:&error];
    if (!objectID && error)
        NSLog(@"%s: %@", __PRETTY_FUNCTION__, error);
    
    return objectID;
    
}

- (NSManagedObjectID *) backingObjectIDForEntity:(NSEntityDescription *)entity resourceIdentifier:(NSString *)resourceIdentifier inContext:(NSManagedObjectContext *)context error:(NSError **)outError {

    NSCParameterAssert(entity);
    NSCParameterAssert(resourceIdentifier);
    NSCParameterAssert([context af_isDescendantOfContext:self.backingManagedObjectContext]);
    
    NSFetchRequest *fetchRequest = [self fetchRequestForObjectIDWithEntity:entity resourceIdentifier:resourceIdentifier];
    
    __block NSArray *results = nil;
    [context performBlockAndWait:^{
       results = [context executeFetchRequest:fetchRequest error:outError];
    }];
    
    return [results lastObject];

}

- (void) importRepresentations:(NSArray *)representations ofEntity:(NSEntityDescription *)entity fromResponse:(NSHTTPURLResponse *)response withContext:(NSManagedObjectContext *)context usingBlock:(void(^)(NSArray *objects))block {

    NSCParameterAssert(representations);
    NSCParameterAssert(entity);
    NSCParameterAssert(response);
    NSCParameterAssert(context);
    NSCParameterAssert(block);
    
    [self.operationQueue addOperation:[RAAsyncOperation operationWithWorker:^(RAAsyncOperationCallback callback) {
    
        
        
    } callback:^(id results) {
    
        
        
    }]];

}

- (void)insertOrUpdateObjectsFromRepresentations:(id)representationOrArrayOfRepresentations ofEntity:(NSEntityDescription *)entity fromResponse:(NSHTTPURLResponse *)response withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error completionBlock:(void (^)(NSArray *managedObjects, NSArray *backingObjects))completionBlock {
    
    NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
    NSDate *lastModified = AFLastModifiedDateFromHTTPHeaders([response allHeaderFields]);
    
    NSArray *representations = nil;
    
    if ([representationOrArrayOfRepresentations isKindOfClass:[NSArray class]]) {
        representations = representationOrArrayOfRepresentations;
    } else if ([representationOrArrayOfRepresentations isKindOfClass:[NSDictionary class]]) {
        representations = @[ representationOrArrayOfRepresentations ];
    } else {
        @throw [NSException exceptionWithName:AFIncrementalStoreRelationshipCardinalityException reason:@"Can not understand the representations." userInfo:nil];
    }
    
    if (![representations count]) {
        if (completionBlock) {
            completionBlock(nil, nil);
        }
        return;
    }

    NSUInteger numberOfRepresentations = [representations count];
    NSMutableArray *mutableManagedObjects = [NSMutableArray arrayWithCapacity:numberOfRepresentations];
    NSMutableArray *mutableBackingObjects = [NSMutableArray arrayWithCapacity:numberOfRepresentations];
    
    for (NSDictionary *representation in representations) {
        
        NSString *resourceIdentifier = [self.HTTPClient resourceIdentifierForRepresentation:representation ofEntity:entity fromResponse:response];
        NSDictionary *attributes = [self.HTTPClient attributesForRepresentation:representation ofEntity:entity fromResponse:response];
        
        __block NSManagedObject *managedObject;
        [context af_performBlockAndWait:^{
            managedObject = [context existingObjectWithID:[self objectIDForEntity:entity withResourceIdentifier:resourceIdentifier] error:nil];
        }];

        [managedObject setValuesForKeysWithDictionary:attributes];
        
        NSManagedObjectID *backingObjectID = [self objectIDForBackingObjectForEntity:entity withResourceIdentifier:resourceIdentifier];
        
        __block NSManagedObject *backingObject;
        [backingContext performBlockAndWait:^{
            if (backingObjectID) {
                backingObject = [backingContext existingObjectWithID:backingObjectID error:nil];
            } else {
                backingObject = [NSEntityDescription insertNewObjectForEntityForName:entity.name inManagedObjectContext:backingContext];
                [backingObject.managedObjectContext obtainPermanentIDsForObjects:@[ backingObject ] error:nil];
            }
        }];
        [backingObject setValue:resourceIdentifier forKey:kAFIncrementalStoreResourceIdentifierAttributeName];
        [backingObject setValue:lastModified forKey:kAFIncrementalStoreLastModifiedAttributeName];
        [backingObject setValuesForKeysWithDictionary:attributes];
        
        if (!backingObjectID) {
            [context insertObject:managedObject];
        }
        
        NSDictionary *relationshipRepresentations = [self.HTTPClient representationsForRelationshipsFromRepresentation:representation ofEntity:entity fromResponse:response];
        for (NSString *relationshipName in relationshipRepresentations) {
            
            NSRelationshipDescription *relationship = [[entity relationshipsByName] valueForKey:relationshipName];
            
            if (!relationship) {
                continue;
            }
            
            id relationshipRepresentation = [relationshipRepresentations objectForKey:relationshipName];
            
            if (!relationshipRepresentation || [relationshipRepresentation isEqual:[NSNull null]] || ![relationshipRepresentation count]) {
                [managedObject setValue:nil forKey:relationshipName];
                [backingObject setValue:nil forKey:relationshipName];
                continue;
            }
            
            [self insertOrUpdateObjectsFromRepresentations:relationshipRepresentation ofEntity:relationship.destinationEntity fromResponse:response withContext:context error:error completionBlock:^(NSArray *managedObjects, NSArray *backingObjects) {
                
                BOOL isToMany = [relationship isToMany];
                BOOL isOrdered = [relationship isOrdered];
                NSString *relationshipName = relationship.name;
                
                id managedRelationshipValue = (isToMany ?
                    (isOrdered ?
                        [NSOrderedSet orderedSetWithArray:managedObjects] :
                        [NSSet setWithArray:managedObjects]) :
                    [managedObjects lastObject]);
                
                id backingRelationshipValue = (isToMany ?
                    (isOrdered ?
                        [NSOrderedSet orderedSetWithArray:backingObjects] :
                        [NSSet setWithArray:backingObjects]) :
                    [backingObjects lastObject]);
                
                [managedObject setValue:managedRelationshipValue forKey:relationshipName];
                [backingObject setValue:backingRelationshipValue forKey:relationshipName];
                
            }];
        }
        
        [mutableManagedObjects addObject:managedObject];
        [mutableBackingObjects addObject:backingObject];
    }
    
    if (completionBlock) {
        completionBlock(mutableManagedObjects, mutableBackingObjects);
    }
    
}

- (id) executeRequest:(NSPersistentStoreRequest *)persistentStoreRequest withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {
    
    NSPersistentStoreRequestType type = persistentStoreRequest.requestType;
    
    if (type == NSFetchRequestType) {
        
        NSFetchRequest *fetchRequest = (NSFetchRequest *)persistentStoreRequest;
        NSCParameterAssert([fetchRequest isKindOfClass:[NSFetchRequest class]]);
        
        return [self executeFetchRequest:fetchRequest withContext:context error:error];
        
    } else if (type == NSSaveRequestType) {
        
        NSSaveChangesRequest *saveChangesRequest = (NSSaveChangesRequest *)persistentStoreRequest;
        NSCParameterAssert([saveChangesRequest isKindOfClass:[NSSaveChangesRequest class]]);
        
        return [self executeSaveChangesRequest:saveChangesRequest withContext:context error:error];
        
    } else {
    
        if (error) {
            *error = [NSError errorWithDomain:AFNetworkingErrorDomain code:0 userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported NSFetchRequestResultType %d", persistentStoreRequest.requestType]
            }];
        }
        
        return nil;
        
    }
    
}

- (NSManagedObject *) backingObjectInContext:(NSManagedObjectContext *)backingContext forManagedObject:(NSManagedObject *)managedObject {

    NSEntityDescription *backingEntity = [NSEntityDescription entityForName:managedObject.entity.name inManagedObjectContext:backingContext];
    NSString *resourceIdentifier = managedObject.af_resourceIdentifier;
    
    if (!backingEntity || !resourceIdentifier)
        return (NSManagedObject *)nil;
    
    NSManagedObjectID *objectID = [self backingObjectIDForEntity:backingEntity resourceIdentifier:resourceIdentifier inContext:backingContext error:nil];
    
    if (!objectID)
        return (NSManagedObject *)nil;
    
    return [backingContext existingObjectWithID:objectID error:nil];;

}

- (void) saveBackingObjects:(NSArray *)backingObjects inContext:(NSManagedObjectContext *)backingContext {

    for (NSManagedObject *backingObject in backingObjects)
        NSCParameterAssert([backingObject af_isPermanent]);
    
    NSError *backingContextSavingError;
    if (![backingContext save:&backingContextSavingError]) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Saving failed." userInfo:@{
            NSUnderlyingErrorKey: backingContextSavingError
        }];
    }
    
    for (NSManagedObject *backingObject in backingObjects)
        NSCParameterAssert(![[backingObject changedValues] count]);

}

- (void) refreshManagedObjects:(NSArray *)managedObjects inContext:(NSManagedObjectContext *)managedContext {

    for (NSManagedObject *managedObject in managedObjects)
        NSCParameterAssert([managedObject af_isPermanent]);
    
    NSSet *refreshedManagedObjects = [NSSet setWithArray:managedObjects];
    
    NSManagedObjectContext *parentContext = managedContext.parentContext;

    [parentContext af_performBlockAndWait:^{
    
        for (NSManagedObject *registeredManagedObject in refreshedManagedObjects) {
            
            NSManagedObject *rootObject = [parentContext objectWithID:registeredManagedObject.objectID];
            
            [rootObject willChangeValueForKey:@"self"];
            [parentContext refreshObject:rootObject mergeChanges:NO];
            [rootObject didChangeValueForKey:@"self"];
            
            NSCParameterAssert(![[rootObject changedValues] count]);
            
        }
        
        [self beginIgnoringRemoteFetchRequestsInContext:parentContext];
        [parentContext processPendingChanges];
        [self endIgnoringRemoteFetchRequestsInContext:parentContext];

    }];
    
    [managedContext af_performBlockAndWait:^{
        
        for (NSManagedObject *registeredManagedObject in refreshedManagedObjects) {
            
            [registeredManagedObject willChangeValueForKey:@"self"];
            [managedContext refreshObject:registeredManagedObject mergeChanges:NO];
            [registeredManagedObject didChangeValueForKey:@"self"];
            
            NSCParameterAssert(![[registeredManagedObject changedValues] count]);
        }
        
        [self beginIgnoringRemoteFetchRequestsInContext:managedContext];
        [managedContext processPendingChanges];
        [self endIgnoringRemoteFetchRequestsInContext:managedContext];
        
    }];
    
    for (NSManagedObject *managedObject in managedObjects)
        NSCParameterAssert(![[managedObject changedValues] count]);

}

- (void) saveBackingManagedObjects:(NSArray *)backingObjects inContext:(NSManagedObjectContext *)backingContext refreshingManagedObjects:(NSArray *)managedObjects inContext:(NSManagedObjectContext *)managedContext {

    [self saveBackingObjects:backingObjects inContext:backingContext];
    [self refreshManagedObjects:managedObjects inContext:managedContext];

}

- (id)executeFetchRequest:(NSFetchRequest *)fetchRequest
              withContext:(NSManagedObjectContext *)context
                    error:(NSError *__autoreleasing *)error
{
    NSURLRequest *request = [self.HTTPClient requestForFetchRequest:fetchRequest withContext:context];
    if ([request URL]) {
        AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
            
            NSArray *representations = [self representationsFromResponseObject:responseObject];
            
            [self performUpdatesWithParentContext:context usingBlock:^(NSManagedObjectContext *childContext) {
                
                [self insertOrUpdateObjectsFromRepresentations:representations ofEntity:fetchRequest.entity fromResponse:operation.response withContext:childContext error:error completionBlock:^(NSArray *managedObjects, NSArray *backingObjects) {
                
                    [self saveBackingManagedObjects:backingObjects inContext:[self backingManagedObjectContext] refreshingManagedObjects:managedObjects inContext:childContext];
                                    
                }];
                
                [self notifyManagedObjectContext:context aboutRequestOperation:operation forFetchRequest:fetchRequest];

            }];
            
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"Error: %@", error);
            [self notifyManagedObjectContext:context aboutRequestOperation:operation forFetchRequest:fetchRequest];
        }];
        
        operation.successCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        operation.failureCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        
        [self notifyManagedObjectContext:context aboutRequestOperation:operation forFetchRequest:fetchRequest];
        [self.HTTPClient enqueueHTTPRequestOperation:operation];
    }
    
    NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
    __block NSArray *results = nil;
    
    NSFetchRequestResultType resultType = fetchRequest.resultType;
    switch (resultType) {
        case NSManagedObjectResultType: {
            fetchRequest = [fetchRequest copy];
            fetchRequest.entity = [NSEntityDescription entityForName:fetchRequest.entityName inManagedObjectContext:backingContext];
            fetchRequest.resultType = NSDictionaryResultType;
            fetchRequest.propertiesToFetch = @[ kAFIncrementalStoreResourceIdentifierAttributeName ];
            [backingContext performBlockAndWait:^{
                results = [backingContext executeFetchRequest:fetchRequest error:error];                
            }];
            
            NSMutableArray *mutableObjects = [NSMutableArray arrayWithCapacity:[results count]];
            for (NSString *resourceIdentifier in [results valueForKeyPath:kAFIncrementalStoreResourceIdentifierAttributeName]) {
                NSManagedObjectID *objectID = [self objectIDForEntity:fetchRequest.entity withResourceIdentifier:resourceIdentifier];
                NSManagedObject *object = [context objectWithID:objectID];
                object.af_resourceIdentifier = resourceIdentifier;
                [mutableObjects addObject:object];
            }
            
            return mutableObjects;
        }
        case NSManagedObjectIDResultType: {
            NSArray *backingObjectIDs = [backingContext executeFetchRequest:fetchRequest error:error];
            NSMutableArray *managedObjectIDs = [NSMutableArray arrayWithCapacity:[backingObjectIDs count]];
            
            for (NSManagedObjectID *backingObjectID in backingObjectIDs) {
                NSManagedObject *backingObject = [backingContext objectWithID:backingObjectID];
                NSString *resourceID = [backingObject valueForKey:kAFIncrementalStoreResourceIdentifierAttributeName];
                [managedObjectIDs addObject:[self objectIDForEntity:fetchRequest.entity withResourceIdentifier:resourceID]];
            }
            
            return managedObjectIDs;
        }
        case NSDictionaryResultType:
        case NSCountResultType:
            return [backingContext executeFetchRequest:fetchRequest error:error];
        default:
            return nil;
    }
}

- (void) obtainPermanentIDForTemporaryObject:(NSManagedObject *)object withResourceIdentifier:(NSString *)resourceIdentifier {
    
    NSCParameterAssert(![object af_isPermanent]);
    
    object.af_resourceIdentifier = resourceIdentifier;
    
    [object willChangeValueForKey:@"objectID"];
    
    NSError *permanentIDsObtainingError = nil;
    BOOL didObtainPermanentIDs = [object.managedObjectContext obtainPermanentIDsForObjects:[NSArray arrayWithObject:object] error:&permanentIDsObtainingError];
    
    if (!didObtainPermanentIDs)
        NSLog(@"%s: %@", __PRETTY_FUNCTION__, permanentIDsObtainingError);

    [object didChangeValueForKey:@"objectID"];
    
    NSCParameterAssert([object af_isPermanent]);

}

- (void) updateRelationshipsOfBackingObject:(NSManagedObject *)backingObject withRelationshipsOfManagedObject:(NSManagedObject *)insertedObject {
    
    NSManagedObjectContext *backingContext = backingObject.managedObjectContext;
    
    [[insertedObject.entity relationshipsByName] enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSRelationshipDescription *relationship, BOOL *stop) {
    
        id requestedRelationship = [insertedObject valueForKey:name];
        if (!requestedRelationship)
            return;
        
        id providedRelationship = nil;
        
        NSManagedObject * (^backingObjectForManagedObject)(NSManagedObject *) = ^ (NSManagedObject *incomingObject) {
        
            return [self backingObjectInContext:backingContext forManagedObject:incomingObject];
        
        };
        
        if ([relationship isToMany]) {
        
            if ([relationship isOrdered]) {
            
                providedRelationship = [NSMutableOrderedSet orderedSet];
                for (NSManagedObject *relationshipObject in (NSOrderedSet *)requestedRelationship) {
                    NSManagedObject *relatedObject = backingObjectForManagedObject(relationshipObject);
                    if (relatedObject) {
                        [(NSMutableOrderedSet *)providedRelationship addObject:relatedObject];
                    } else {
                        NSLog(@"%s: lost track of relationship object %@", __PRETTY_FUNCTION__, relationshipObject);
                    }
                }
            
            } else {
            
                providedRelationship = [NSMutableSet set];
                for (NSManagedObject *relationshipObject in (NSSet *)requestedRelationship) {
                    NSManagedObject *relatedObject = backingObjectForManagedObject(relationshipObject);
                    if (relatedObject) {
                        [(NSMutableSet *)providedRelationship addObject:relatedObject];
                    } else {
                        NSLog(@"%s: lost track of relationship object %@", __PRETTY_FUNCTION__, relationshipObject);
                    }
                }
                
            }
        
        } else {
        
            NSManagedObject *relationshipObject = (NSManagedObject *)requestedRelationship;
            NSManagedObject *relatedObject = backingObjectForManagedObject(relationshipObject);
            if (relatedObject) {
                providedRelationship = relatedObject;
            } else {
                NSLog(@"%s: lost track of relationship object %@", __PRETTY_FUNCTION__, relationshipObject);
            }
        
        }
        
        [backingObject setValue:providedRelationship forKey:name];
        
    }];

}

- (void) assertManagedObject:(NSManagedObject *)managedObject hasAssociationsEquivalentToBackingObject:(NSManagedObject *)backingObject {

    NSDictionary *backingRelationships = backingObject.entity.relationshipsByName;
    NSDictionary *managedRelationships = managedObject.entity.relationshipsByName;
    NSCParameterAssert([backingRelationships count] == [managedRelationships count]);
    NSCParameterAssert([[backingRelationships allKeys] isEqualToArray:[managedRelationships allKeys]]);
    [backingRelationships enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSRelationshipDescription*backingRelationship, BOOL *stop) {
        if ([backingObject valueForKey:name]) {
            NSCParameterAssert([managedObject valueForKey:name]);
        } else {
            NSCParameterAssert(![managedObject valueForKey:name]);
        }
    }];

}

- (NSArray *) operationsForInsertedObject:(NSManagedObject *)insertedObject {

    AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
    NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
    
    if (![httpClient respondsToSelector:@selector(requestForInsertedObject:)])
        return @[];

    NSURLRequest *request = [httpClient requestForInsertedObject:insertedObject];
    if (!request)
        return @[];
    
    AFHTTPRequestOperation *operation = [httpClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        NSEntityDescription *entity = insertedObject.entity;
        NSHTTPURLResponse *response = operation.response;
        
        NSString *resourceIdentifier = [self.HTTPClient resourceIdentifierForRepresentation:responseObject ofEntity:entity fromResponse:response];

        NSDictionary *attributes = [self.HTTPClient attributesForRepresentation:responseObject ofEntity:entity fromResponse:response];
        
        NSManagedObjectID *objectID = [self objectIDForEntity:[insertedObject entity] withResourceIdentifier:resourceIdentifier];
        insertedObject.af_resourceIdentifier = resourceIdentifier;
        [insertedObject setValuesForKeysWithDictionary:attributes];
        
        __block NSManagedObject *backingObject = nil;
        
        if (objectID) {
            [backingContext performBlockAndWait:^{
                backingObject = [backingContext existingObjectWithID:objectID error:nil];
            }];
        }
        
        if (!backingObject) {
            backingObject = [NSEntityDescription insertNewObjectForEntityForName:insertedObject.entity.name inManagedObjectContext:backingContext];
            [backingObject.managedObjectContext obtainPermanentIDsForObjects:@[ backingObject ] error:nil];
        }
        
        NSCParameterAssert(backingObject);
        NSCParameterAssert(backingObject.objectID);
        NSCParameterAssert(![backingObject.objectID isTemporaryID]);
        
        [backingObject setValue:resourceIdentifier forKey:kAFIncrementalStoreResourceIdentifierAttributeName];
        [backingObject setValuesForKeysWithDictionary:attributes];
        
        [self updateRelationshipsOfBackingObject:backingObject withRelationshipsOfManagedObject:insertedObject];
                        
        [self obtainPermanentIDForTemporaryObject:insertedObject withResourceIdentifier:resourceIdentifier];
        
        [self assertManagedObject:insertedObject hasAssociationsEquivalentToBackingObject:backingObject];
        
        [self performUpdatesWithParentContext:insertedObject.managedObjectContext usingBlock:^(NSManagedObjectContext *childContext) {
            
            [self insertOrUpdateObjectsFromRepresentations:@[ responseObject ] ofEntity:entity fromResponse:operation.response withContext:childContext error:nil completionBlock:^(NSArray *managedObjects, NSArray *backingObjects) {
            
                NSCParameterAssert([managedObjects count] == 1);
                NSCParameterAssert([backingObjects count] == 1);
            
                [self saveBackingManagedObjects:backingObjects inContext:[self backingManagedObjectContext] refreshingManagedObjects:managedObjects inContext:childContext];
                                
            }];
            
        }];
                        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        
        NSLog(@"Insert Error: %@", error);
        
    }];
    
    return @[ operation ];

}

- (NSArray *) operationsForUpdatedObject:(NSManagedObject *)updatedObject {

    AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
    NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
    
    if (![httpClient respondsToSelector:@selector(requestForUpdatedObject:)])
        return @[];
    
    NSURLRequest *request = [httpClient requestForUpdatedObject:updatedObject];
    if (!request)
        return nil;
    
    AFHTTPRequestOperation *operation = [httpClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
    
        [updatedObject setValuesForKeysWithDictionary:[httpClient attributesForRepresentation:responseObject ofEntity:updatedObject.entity fromResponse:operation.response]];
        
        [backingContext performBlockAndWait:^{
            NSManagedObject *backingObject = [backingContext existingObjectWithID:updatedObject.objectID error:nil];
            [backingObject setValuesForKeysWithDictionary:[updatedObject dictionaryWithValuesForKeys:nil]];
            [backingContext save:nil];
        }];
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        
        NSLog(@"Update Error: %@", error);
        
    }];
    
    return @[ operation ];

}

- (NSArray *) operationsForDeletedObject:(NSManagedObject *)deletedObject {

    AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
    NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
    
    if (![self.HTTPClient respondsToSelector:@selector(requestForDeletedObject:)])
        return @[];
    
    NSURLRequest *request = [httpClient requestForDeletedObject:deletedObject];
    if (!request)
        return nil;
    
    AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
    
        [backingContext performBlockAndWait:^{
            
            NSManagedObject *backingObject = [backingContext existingObjectWithID:deletedObject.objectID error:nil];
            [backingContext deleteObject:backingObject];
            [backingContext save:nil];
            
        }];
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        
        NSLog(@"Delete Error: %@", error);
        
    }];
    
    return @[ operation ];

}

- (NSArray *) operationsForSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest {
    
    NSMutableArray *ops = [NSMutableArray array];
    
    NSSet *insertedObjects = [saveChangesRequest insertedObjects];
    NSSet *updatedObjects = [saveChangesRequest updatedObjects];
    NSSet *deletedObjects = [saveChangesRequest deletedObjects];
    
    for (NSManagedObject *insertedObject in insertedObjects)
        [ops addObjectsFromArray:[self operationsForInsertedObject:insertedObject]];
    
    for (NSManagedObject *updatedObject in updatedObjects)
        [ops addObjectsFromArray:[self operationsForUpdatedObject:updatedObject]];

    for (NSManagedObject *deletedObject in deletedObjects)
        [ops addObjectsFromArray:[self operationsForDeletedObject:deletedObject]];
    
    return ops;
    
}

- (id) executeSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {

    //  TBD: AFIncrementalStore should subclass NSOperation directly, or provide a async harness that invokes customer-provided blocks, and allow overriding methods that emit the blocks and blocks that call callback blocks.  Give all the save components a scratchpad to play on, and if everything finished, store everything in a batch.  A potential implementation will involve a change request tree that gets appended by each save operation (emitted by -operationsForSaveChangesRequest: operations).
    
    //  This is related to the Undo Management problem: the incremental store does asynchronous data fulfillment, so if the customer changed some more data and things do not go through, we can not even revert.

    NSArray *operations = [self operationsForSaveChangesRequest:saveChangesRequest];
    if ([operations count]) {
    
        [self notifyManagedObjectContext:context aboutRequestOperations:operations forSaveChangesRequest:saveChangesRequest];
        
        [self.HTTPClient enqueueBatchOfHTTPRequestOperations:operations progressBlock:^(NSUInteger numberOfFinishedOperations, NSUInteger totalNumberOfOperations) {
            
            //  ?
            
        } completionBlock:^(NSArray *operations) {
        
            [self notifyManagedObjectContext:context aboutRequestOperations:operations forSaveChangesRequest:saveChangesRequest];
            
        }];
    
    }
    
    return @[];
    
}

#pragma mark -

- (BOOL) shouldFetchRemoteAttributeValuesForObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context {

    if ([self isIgnoringRemoteFetchRequestsInContext:context])
        return NO;

    NSString *resourceIdentifier = [self referenceObjectForObjectID:objectID];
    if (!resourceIdentifier || (resourceIdentifier && ![resourceIdentifier isKindOfClass:[NSString class]]))
        return NO;
    
    AFHTTPClient<AFIncrementalStoreHTTPClient> *HTTPClient = self.HTTPClient;
    if (!HTTPClient)
        return NO;
    
    if (![HTTPClient respondsToSelector:@selector(shouldFetchRemoteAttributeValuesForObjectWithID:inManagedObjectContext:)])
        return NO;
    
    return [HTTPClient shouldFetchRemoteAttributeValuesForObjectWithID:objectID inManagedObjectContext:context];

}

- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID
                                         withContext:(NSManagedObjectContext *)context
                                               error:(NSError *__autoreleasing *)error
{
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:[[objectID entity] name]];
    fetchRequest.resultType = NSDictionaryResultType;
    fetchRequest.fetchLimit = 1;
    fetchRequest.includesSubentities = NO;
    fetchRequest.propertiesToFetch = [[[NSEntityDescription entityForName:fetchRequest.entityName inManagedObjectContext:context] attributesByName] allKeys];
    
    //  Attempting to fetch an empty entity would cause issues
    NSCParameterAssert([fetchRequest.propertiesToFetch count]);
    
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K = %@", kAFIncrementalStoreResourceIdentifierAttributeName, [self referenceObjectForObjectID:objectID]];
    
    __block NSArray *results;
    NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
    [backingContext performBlockAndWait:^{
        results = [backingContext executeFetchRequest:fetchRequest error:error];
    }];
    NSDictionary *attributeValues = [results lastObject] ?: [NSDictionary dictionary];

    NSIncrementalStoreNode *node = [[NSIncrementalStoreNode alloc] initWithObjectID:objectID withValues:attributeValues version:1];
    
    if ([self.HTTPClient respondsToSelector:@selector(shouldFetchRemoteAttributeValuesForObjectWithID:inManagedObjectContext:)] && [self.HTTPClient shouldFetchRemoteAttributeValuesForObjectWithID:objectID inManagedObjectContext:context]) {
        
        if (attributeValues) {
            
            NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
            childContext.parentContext = context;
            childContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
            
            NSMutableURLRequest *request = [self.HTTPClient requestWithMethod:@"GET" pathForObjectWithID:objectID withContext:context];
            
            if ([request URL]) {
                if ([attributeValues valueForKey:kAFIncrementalStoreLastModifiedAttributeName]) {
                    [request setValue:[[attributeValues valueForKey:kAFIncrementalStoreLastModifiedAttributeName] description] forHTTPHeaderField:@"If-Modified-Since"];
                }
                
                AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, NSDictionary *representation) {
                    NSManagedObject *managedObject = [childContext existingObjectWithID:objectID error:error];
                    
                    NSMutableDictionary *mutableAttributeValues = [attributeValues mutableCopy];
                    [mutableAttributeValues addEntriesFromDictionary:[self.HTTPClient attributesForRepresentation:representation ofEntity:managedObject.entity fromResponse:operation.response]];
                    [managedObject setValuesForKeysWithDictionary:mutableAttributeValues];
                    
                    NSEntityDescription *entity = objectID.entity;
                    NSString *resourceID = [self referenceObjectForObjectID:objectID];
                    NSManagedObjectContext *backingContext = self.backingManagedObjectContext;
                    
                    [backingContext performBlock:^{
                        
                        NSError *backingObjectIDError = nil;
                        NSManagedObjectID *backingObjectID = [self backingObjectIDForEntity:objectID.entity resourceIdentifier:resourceID inContext:backingContext error:&backingObjectIDError];

                        NSManagedObject *backingObject = [backingContext existingObjectWithID:backingObjectID error:nil];
                        [backingObject setValuesForKeysWithDictionary:mutableAttributeValues];
                        
                        [self saveBackingManagedObjects:@[ backingObject ] inContext:backingContext refreshingManagedObjects:@[ managedObject ] inContext:childContext];
                        
                    }];
                    
                } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                    
                    NSLog(@"%s: %@, %@", __PRETTY_FUNCTION__, operation, error);
                    
                }];
                
                [self.HTTPClient enqueueHTTPRequestOperation:operation];
                
            }
        }
    }
    
    return node;
    
}

- (BOOL) shouldFetchRemoteValuesForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context {

    if ([self isIgnoringRemoteFetchRequestsInContext:context])
        return NO;

    NSString *resourceIdentifier = [self referenceObjectForObjectID:objectID];
    if (!resourceIdentifier || (resourceIdentifier && ![resourceIdentifier isKindOfClass:[NSString class]]))
        return NO;
    
    AFHTTPClient<AFIncrementalStoreHTTPClient> *HTTPClient = self.HTTPClient;
    if (!HTTPClient)
        return NO;
    
    if (![HTTPClient respondsToSelector:@selector(shouldFetchRemoteValuesForRelationship:forObjectWithID:inManagedObjectContext:)])
        return NO;
    
    return [HTTPClient shouldFetchRemoteValuesForRelationship:relationship forObjectWithID:objectID inManagedObjectContext:context];

}

- (id)newValueForRelationship:(NSRelationshipDescription *)relationship
              forObjectWithID:(NSManagedObjectID *)objectID
                  withContext:(NSManagedObjectContext *)context
                        error:(NSError *__autoreleasing *)error
{

    if ([self shouldFetchRemoteValuesForRelationship:relationship forObjectWithID:objectID withContext:context]) {
    
        [self fetchNewValueForRelationship:relationship forObjectWithID:objectID withContext:context usingBlock:^(id representationOrRepresentations, NSURLResponse *response, NSError *error) {
            
            //  ?
            
        }];
        
    }
    
    NSManagedObjectID *backingObjectID = [self objectIDForBackingObjectForEntity:[objectID entity] withResourceIdentifier:[self referenceObjectForObjectID:objectID]];
    NSManagedObject *backingObject = (backingObjectID == nil) ? nil : [[self backingManagedObjectContext] existingObjectWithID:backingObjectID error:nil];
    
    if (backingObject && ![backingObject hasChanges]) {
        id backingRelationshipObject = [backingObject valueForKeyPath:relationship.name];
        if ([relationship isToMany]) {
            NSMutableArray *mutableObjects = [NSMutableArray arrayWithCapacity:[backingRelationshipObject count]];
            for (NSString *resourceIdentifier in [backingRelationshipObject valueForKeyPath:kAFIncrementalStoreResourceIdentifierAttributeName]) {
                NSManagedObjectID *objectID = [self objectIDForEntity:relationship.destinationEntity withResourceIdentifier:resourceIdentifier];
                [mutableObjects addObject:objectID];
            }
                            
            return mutableObjects;            
        } else {
            NSString *resourceIdentifier = [backingRelationshipObject valueForKeyPath:kAFIncrementalStoreResourceIdentifierAttributeName];
            NSManagedObjectID *objectID = [self objectIDForEntity:relationship.destinationEntity withResourceIdentifier:resourceIdentifier];
            
            return objectID ?: [NSNull null];
        }
    } else {
        if ([relationship isToMany]) {
            return [NSArray array];
        } else {
            return [NSNull null];
        }
    }
}

- (void) beginIgnoringRemoteFetchRequestsInContext:(NSManagedObjectContext *)context {

    [context af_incrementIgnoringCount];

}

- (void) endIgnoringRemoteFetchRequestsInContext:(NSManagedObjectContext *)context {

    [context af_decrementIgnoringCount];

}

- (BOOL) isIgnoringRemoteFetchRequestsInContext:(NSManagedObjectContext *)context {
    
    return !![context af_ignoringCount];
    
}

- (void) performUpdatesWithParentContext:(NSManagedObjectContext *)context usingBlock:(void(^)(NSManagedObjectContext *childContext))block {
    
    __weak typeof(context) wContext = context;
    
    [self.operationQueue addOperation:[RAAsyncOperation operationWithWorker:^(RAAsyncOperationCallback callback) {
    
        if (!wContext) {
            callback((id)kCFBooleanFalse);
            return;
        }
        
        NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
        childContext.parentContext = wContext;
        childContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
        
        block(childContext);
        callback((id)kCFBooleanTrue);

    } trampoline:^(IRAsyncOperationInvoker callback) {
        
        dispatch_async(self.dispatchQueue, callback);
        
    } callback:^(id results) {
        
        //  ?
        
    } trampoline:^(IRAsyncOperationInvoker callback) {
        
        dispatch_async(self.dispatchQueue, callback);            
        
    }]];

    
}

- (NSArray *) representationsFromResponseObject:(id)responseObject {

    id representationOrArrayOfRepresentations = [self.HTTPClient representationOrArrayOfRepresentationsFromResponseObject:responseObject];
    
    if ([representationOrArrayOfRepresentations isKindOfClass:[NSArray class]])
        return representationOrArrayOfRepresentations;
    
    return @[ representationOrArrayOfRepresentations ];
    
}

- (void) fetchNewValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context usingBlock:(void(^)(id representationOrRepresentations, NSURLResponse *response, NSError *error))block {
    
    NSCParameterAssert(relationship);
    NSCParameterAssert(objectID);
    NSCParameterAssert(context);
    NSCParameterAssert(block);
    
    if (![self shouldFetchRemoteValuesForRelationship:relationship forObjectWithID:objectID withContext:context]) {
        block(nil, nil, nil);
        return;
    }
    
    NSURLRequest *request = [self requestForRelationship:relationship forObjectWithID:objectID context:context];
    if (!request.URL)
        return;
    
    NSManagedObject *existingObject = [context existingObjectWithID:objectID error:nil];
    if (existingObject && [existingObject hasChanges])
        return;
    
    __weak typeof(self.HTTPClient) wClient = self.HTTPClient;
    __weak typeof(self) wSelf = self;
    
    AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
    
        NSArray *representations = [self representationsFromResponseObject:responseObject];
        if (![representations count]) {
            block(responseObject, operation.response, nil);
            return;
        }
        
        [self performUpdatesWithParentContext:context usingBlock:^(NSManagedObjectContext *childContext) {
            
            [self insertOrUpdateObjectsFromRepresentations:representations ofEntity:relationship.destinationEntity fromResponse:operation.response withContext:childContext error:nil completionBlock:^(NSArray *managedObjects, NSArray *backingObjects) {

                NSManagedObject *managedObject = [childContext objectWithID:objectID];
                NSString *referenceObject = [self referenceObjectForObjectID:objectID];
                NSManagedObjectID *backingObjectID = [self backingObjectIDForEntity:objectID.entity resourceIdentifier:referenceObject inContext:self.backingManagedObjectContext error:nil];
                
                NSManagedObject *backingObject = [[self backingManagedObjectContext] existingObjectWithID:backingObjectID error:nil];
                
                id managedRelationshipValue =
                    [relationship isToMany] ?
                        ([relationship isOrdered] ?
                            [NSOrderedSet orderedSetWithArray:managedObjects] :
                            [NSSet setWithArray:managedObjects]) :
                        [managedObjects lastObject];
                
                id backingRelationshipValue =
                    [relationship isToMany] ?
                        ([relationship isOrdered] ?
                            [NSOrderedSet orderedSetWithArray:backingObjects] :
                            [NSSet setWithArray:backingObjects]) :
                        [backingObjects lastObject];
                
                [managedObject setValue:managedRelationshipValue forKey:relationship.name];
                [backingObject setValue:backingRelationshipValue forKey:relationship.name];
                
                [self saveBackingManagedObjects:backingObjects inContext:[self backingManagedObjectContext] refreshingManagedObjects:managedObjects inContext:childContext];
                
                block(responseObject, operation.response, nil);
                
            }];           
            
        }];
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        
        NSLog(@"Error: %@, %@", operation, error);
        
    }];
    
    operation.successCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    operation.failureCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

    [self.HTTPClient enqueueHTTPRequestOperation:operation];

}

- (NSURLRequest *) requestForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID context:(NSManagedObjectContext *)context {

    return [self.HTTPClient requestWithMethod:@"GET" pathForRelationship:relationship forObjectWithID:objectID withContext:context];

}

#pragma mark - NSIncrementalStore

- (void)managedObjectContextDidRegisterObjectsWithIDs:(NSArray *)objectIDs {
    [super managedObjectContextDidRegisterObjectsWithIDs:objectIDs];
    for (NSManagedObjectID *objectID in objectIDs) {
        id key = [self referenceObjectForObjectID:objectID];
        if (!key) {
            continue;
        }
        
        NSMutableDictionary *objectIDsByResourceIdentifier = _registeredObjectIDsByResourceIdentifier[objectID.entity.name];
        if (!objectIDsByResourceIdentifier) {
            objectIDsByResourceIdentifier = [NSMutableDictionary dictionary];
            _registeredObjectIDsByResourceIdentifier[objectID.entity.name] = objectIDsByResourceIdentifier;
        }
        objectIDsByResourceIdentifier[key] = objectID;
    }
}

- (void)managedObjectContextDidUnregisterObjectsWithIDs:(NSArray *)objectIDs {
    [super managedObjectContextDidUnregisterObjectsWithIDs:objectIDs];
    for (NSManagedObjectID *objectID in objectIDs) {
        [_registeredObjectIDsByResourceIdentifier[objectID.entity.name] removeObjectForKey:[self referenceObjectForObjectID:objectID]];
    }
}

@end
