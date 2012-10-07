//  AFIncrementalStore+ObjectIDs.h

#import "AFIncrementalStore.h"

@class AFIncrementalStoreReferenceObject;
@interface AFIncrementalStore (ObjectIDs)

- (NSManagedObjectID *) objectIDForEntity:(NSEntityDescription *)entity withResourceIdentifier:(NSString *)resourceIdentifier;
- (NSManagedObjectID *) objectIDForBackingObjectForEntity:(NSEntityDescription *)entity withResourceIdentifier:(NSString *)resourceIdentifier;

- (NSManagedObjectID *) newObjectIDForEntity:(NSEntityDescription *)entity referenceObject:(AFIncrementalStoreReferenceObject *)data;
- (AFIncrementalStoreReferenceObject *) referenceObjectForObjectID:(NSManagedObjectID *)objectID;

@end
