//  AFIncrementalStore+Saving.h

#import "AFIncrementalStore.h"

@interface AFIncrementalStore (Saving)

- (id) executePersistentStoreSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest withContext:(NSManagedObjectContext *)context error:(NSError **)error;

@end
