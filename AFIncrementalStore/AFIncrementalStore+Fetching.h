//  AFIncrementalStore+Fetching.h

#import "AFIncrementalStore.h"

@interface AFIncrementalStore (Fetching)

- (id) executePersistentStoreFetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context error:(NSError **)error;

- (void) executeRemoteFetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context completion:(void(^)(BOOL didFinish))block;

- (void) handleRemoteFetchRequest:(NSFetchRequest *)fetchRequest finishedWithResponse:(NSHTTPURLResponse *)response savingIntoContext:(NSManagedObjectContext *)context completion:(void(^)(void))block;

- (id) executeLocalFetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context error:(NSError * __autoreleasing *)error;

@end
