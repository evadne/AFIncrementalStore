//  AFIncrementalStoreReferenceObject.h

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@interface AFIncrementalStoreReferenceObject : NSObject <NSCopying>

+ (id) objectWithEntity:(NSEntityDescription *)entity resourceIdentifier:(NSString *)identifier;

- (id) initWithEntity:(NSEntityDescription *)entity resourceIdentifier:(NSString *)identifier;

@property (nonatomic, readonly, strong) NSEntityDescription *entity;
@property (nonatomic, readonly, copy) NSString *resourceIdentifier;

@end
