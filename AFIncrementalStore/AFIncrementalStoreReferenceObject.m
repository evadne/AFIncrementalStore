//  AFIncrementalStoreReferenceObject.m

#import "AFIncrementalStoreReferenceObject.h"

@implementation AFIncrementalStoreReferenceObject
@synthesize entity = _entity;
@synthesize resourceIdentifier = _resourceIdentifier;

+ (id) objectWithEntity:(NSEntityDescription *)entity resourceIdentifier:(NSString *)identifier {

	return [[self alloc] initWithEntity:entity resourceIdentifier:identifier];

}

- (id) initWithEntity:(NSEntityDescription *)entity resourceIdentifier:(NSString *)identifier {

	NSCParameterAssert([entity isKindOfClass:[NSEntityDescription class]]);
	NSCParameterAssert(!identifier || [identifier isKindOfClass:[NSString class]]);
	
	self = [super init];
	if (!self)
		return nil;
	
	_entity = entity;
	_resourceIdentifier = [identifier copy];
	
	return self;
	
}

- (id) init {

	return [self initWithEntity:nil resourceIdentifier:nil];

}

- (BOOL) isEqual:(AFIncrementalStoreReferenceObject *)object {

	if (![object isKindOfClass:[self class]])
		return [super isEqual:object];
	
	if (!self.entity || !object.entity || ![self.entity.name isEqual:object.entity.name])
		return NO;

	if (!self.resourceIdentifier || !object.resourceIdentifier || ![self.resourceIdentifier isEqual:object.resourceIdentifier])
		return NO;
	
	return YES;
	
}

- (id) copyWithZone:(NSZone *)zone {

	return [[[self class] alloc] initWithEntity:self.entity resourceIdentifier:self.resourceIdentifier];

}

- (NSUInteger) hash {

	return [self.entity.name hash] ^ [self.resourceIdentifier hash];

}

- (NSString *) description {

	return [NSString stringWithFormat:@"<%@: %p { Entity = %@, Resource Identifier = %@ }>", NSStringFromClass([self class]), self, self.entity.name, self.resourceIdentifier];

}

@end
