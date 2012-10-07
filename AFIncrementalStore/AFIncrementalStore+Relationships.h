//  AFIncrementalStore+Relationships.h

#import "AFIncrementalStore.h"

@interface AFIncrementalStore (Relationships)

- (void) fetchRemoteValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context completion:(void(^)(void))block;

- (void) handleRemoteValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID finishedLoadingWithResponse:(NSHTTPURLResponse *)response savingIntoContext:(NSManagedObjectContext *)context completion:(void(^)(void))block;

- (id) fetchLocalValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError * __autoreleasing *)error;

@end
