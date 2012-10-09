//  AFIncrementalStore+ObjectIDs.h

#import "AFIncrementalStore.h"

@class AFIncrementalStoreReferenceObject;
@interface AFIncrementalStore (ObjectIDs)

- (NSManagedObjectID *) objectIDForEntity:(NSEntityDescription *)entity withResourceIdentifier:(NSString *)resourceIdentifier;
- (NSManagedObjectID *) objectIDForBackingObjectForEntity:(NSEntityDescription *)entity withResourceIdentifier:(NSString *)resourceIdentifier;

- (NSManagedObjectID *) newObjectIDForEntity:(NSEntityDescription *)entity resourceIdentifier:(NSString *)resourceIdentifier;
- (NSString *) resourceIdentifierForObjectID:(NSManagedObjectID *)objectID;

@end
