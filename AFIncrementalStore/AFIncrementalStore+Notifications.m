//  AFIncrementalStore+Notifications.m

#import "AFIncrementalStore+Notifications.h"

@implementation AFIncrementalStore (Notifications)

- (void) notifyManagedObjectContext:(NSManagedObjectContext *)context aboutRequestOperation:(AFHTTPRequestOperation *)operation {
	
	[self notifyManagedObjectContext:context aboutRequestOperation:operation forPersistentStoreRequest:nil];
	
}

- (void) notifyManagedObjectContext:(NSManagedObjectContext *)context aboutRequestOperation:(AFHTTPRequestOperation *)operation forPersistentStoreRequest:(NSPersistentStoreRequest *)request {

	if (![NSThread isMainThread]) {
	
			dispatch_async(dispatch_get_main_queue(), ^{

					[self notifyManagedObjectContext:context aboutRequestOperation:operation forPersistentStoreRequest:request];

			});
			
			return;

	}

	NSString *notificationName = [operation isFinished] ? AFIncrementalStoreContextDidFetchRemoteValues : AFIncrementalStoreContextWillFetchRemoteValues;

	NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
	[userInfo setObject:operation forKey:AFIncrementalStoreRequestOperationKey];
	if (request) {
		[userInfo setObject:request forKey:AFIncrementalStorePersistentStoreRequestKey];
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:context userInfo:userInfo];
		
}

@end
