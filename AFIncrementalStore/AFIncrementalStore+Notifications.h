//  AFIncrementalStore+Notifications.h

#import "AFIncrementalStore.h"

@interface AFIncrementalStore (Notifications)

- (void) notifyManagedObjectContext:(NSManagedObjectContext *)context aboutRequestOperation:(AFHTTPRequestOperation *)operation;
	
- (void) notifyManagedObjectContext:(NSManagedObjectContext *)context aboutRequestOperation:(AFHTTPRequestOperation *)operation forPersistentStoreRequest:(NSPersistentStoreRequest *)request;

@end
