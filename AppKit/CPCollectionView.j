/*
 * CPCollectionView.j
 * AppKit
 *
 * Created by Francisco Tolmasky.
 * Copyright 2008, 280 North, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

@import <Foundation/CPArray.j>
@import <Foundation/CPData.j>
@import <Foundation/CPIndexSet.j>
@import <Foundation/CPKeyedArchiver.j>
@import <Foundation/CPKeyedUnarchiver.j>

@import <AppKit/CPView.j>
@import <AppKit/CPCollectionViewItem.j>
@import <AppKit/CPCompatibility.j>

/*!
    @ingroup appkit
    @class CPCollectionView

    This class displays an array as a grid of objects, where each object is represented by a view.
    The view is controlled by creating a CPCollectionViewItem and specifying its view, then
    setting that item as the collection view prototype.

    @par Delegate Methods

    @delegate - (void)collectionViewDidChangeSelection:(CPCollectionView)collectionView;
    Called when the selection in the collection view has changed.
    @param collectionView the collection view who's selection changed

    @delegate - (void)collectionView:(CPCollectionView)collectionView didDoubleClickOnItemAtIndex:(int)index;
    Called when the user double-clicks on an item in the collection view.
    @param collectionView the collection view that received the double-click
    @param index the index of the item that received the double-click

    @delegate - (CPData)collectionView:(CPCollectionView)collectionView dataForItemsAtIndexes:(CPIndexSet)indices forType:(CPString)aType;
    Invoked to obtain data for a set of indices.
    @param collectionView the collection view to obtain data for
    @param indices the indices to return data for
    @param aType the data type
    @return a data object containing the index items

    @delegate - (CPArray)collectionView:(CPCollectionView)collectionView dragTypesForItemsAtIndexes:(CPIndexSet)indices;
    Invoked to obtain the data types supported by the specified indices for placement on the pasteboard.
    @param collectionView the collection view the items reside in
    @param indices the indices to obtain drag types
    @return an array of drag types (CPString)
*/

@implementation CPCollectionView : CPView
{
    CPArray                 _content;
    CPArray                 _items;

    CPData                  _itemData;
    CPCollectionViewItem    _itemPrototype;
    CPCollectionViewItem    _itemForDragging;
    CPMutableArray          _cachedItems;

    unsigned                _maxNumberOfRows;
    unsigned                _maxNumberOfColumns;

    CGSize                  _minItemSize;
    CGSize                  _maxItemSize;

    CPArray                 _backgroundColors;

    float                   _tileWidth;

    BOOL                    _isSelectable;
    BOOL                    _allowsMultipleSelection;
    BOOL                    _allowsEmptySelection;
    CPIndexSet              _selectionIndexes;

    CGSize                  _itemSize;

    float                   _horizontalMargin;
    float                   _verticalMargin;

    unsigned                _numberOfRows;
    unsigned                _numberOfColumns;

    id                      _delegate;

    CPEvent                 _mouseDownEvent;

    BOOL                    _needsMinMaxItemSizeUpdate;
    CGSize                  _storedFrameSize;

    BOOL                    _uniformSubviewsResizing @accessors(property=uniformSubviewsResizing);
    BOOL                    _lockResizing;
}

- (id)initWithFrame:(CGRect)aFrame
{
    self = [super initWithFrame:aFrame];

    if (self)
    {
        _maxNumberOfRows = 0;
        _maxNumberOfColumns = 0;

        _minItemSize = CGSizeMakeZero();
        _maxItemSize = CGSizeMakeZero();

        [self setBackgroundColors:nil];

        _verticalMargin = 5.0;
        _isSelectable = YES;
        _allowsEmptySelection = YES;

        [self _init];
    }

    return self;
}

- (void)_init
{
        _content = [];

        _items = [];
        _cachedItems = [];

        _numberOfColumns = CPNotFound;
        _numberOfRows = CPNotFound;

        _itemSize = CGSizeMakeZero();

        _selectionIndexes = [CPIndexSet indexSet];

        _storedFrameSize = CGSizeMakeZero();

        _needsMinMaxItemSizeUpdate = YES;
        _uniformSubviewsResizing = NO;
        _lockResizing = NO;

        [self setAutoresizesSubviews:NO];
        [self setAutoresizingMask:0];
}

/*!
    Sets the item prototype to \c anItem

    The item prototype should implement the CPCoding protocol
    because the item is copied by archiving and unarchiving the
    prototypal view.

    Example:

    <pre>
      @implement MyCustomView : CPCollectionViewItem
      {
          CPArray   items   @accessors;
      }

      - (id)initWithFrame:(CGRect)aFrame
      {
        self = [super initWithFrame:aFrame];
        if (self)
        {
          items = [];
        }
        return self;
      }

      - (id)initWithCoder:(CPCoder)aCoder
      {
        self = [super initWithCoder:aCoder];
        items = [aCoder decodeObjectForKey:@"KEY"];
        return self;
      }

      - (void)encodeWithCoder:(CPCoder)aCoder
      {
        [aCoder encodeObject:items forKey:@"KEY"];
        [super encodeWithCoder:aCoder];
      }

      @end
    </pre>

    This will allow the collection view to create multiple 'clean' copies
    of the item prototype which will maintain the original values for item
    and all of the properties archived by the super class.

    @param anItem the new item prototype
*/
- (void)setItemPrototype:(CPCollectionViewItem)anItem
{
    _cachedItems = [];
    _itemData = nil;
    _itemForDragging = nil;
    _itemPrototype = anItem;

    [self reloadContentCachingRemovedItems:NO];
}

/*!
    Returns the current item prototype
*/
- (CPCollectionViewItem)itemPrototype
{
    return _itemPrototype;
}

/*!
    Returns a collection view item for \c anObject.
    @param anObject the object to be represented.
*/
- (CPCollectionViewItem)newItemForRepresentedObject:(id)anObject
{
    var item = nil;

    if (_cachedItems.length)
        item = _cachedItems.pop();

    else
        item = [_itemPrototype copy];

    [item setRepresentedObject:anObject];
    [[item view] setFrameSize:_itemSize];

    return item;
}

// Working with the Responder Chain
/*!
    Returns \c YES by default.
*/
- (BOOL)acceptsFirstResponder
{
    return YES;
}

/*!
    Returns whether the receiver is currently the first responder.
*/
- (BOOL)isFirstResponder
{
    return [[self window] firstResponder] === self;
}

// Setting the Content
/*!
    Sets the content of the collection view to the content in \c anArray.
    This array can be of any type, and each element will be passed to the \c -setRepresentedObject: method.
    It's the responsibility of your custom collection view item to interpret the object.

    If the new content array is smaller than the previous one, note that [receiver selectionIndexes] may
    refer to out of range indices. \c selectionIndexes is not changed as a result of calling the
    \c setContent: method.

    @param anArray a content array
*/
- (void)setContent:(CPArray)anArray
{
    _content = anArray;

    [self reloadContent];
}

/*!
    Returns the collection view content array
*/
- (CPArray)content
{
    return _content;
}

/*!
    Returns the collection view items.
*/
- (CPArray)items
{
    return _items;
}

// Setting the Selection Mode
/*!
    Sets whether the user is allowed to select items
    @param isSelectable \c YES allows the user to select items.
*/
- (void)setSelectable:(BOOL)isSelectable
{
    if (_isSelectable == isSelectable)
        return;

    _isSelectable = isSelectable;

    if (!_isSelectable)
    {
        var index = CPNotFound,
            itemCount = [_items count];

        // Be wary of invalid selection ranges since setContent: does not clear selection indexes.
        while ((index = [_selectionIndexes indexGreaterThanIndex:index]) != CPNotFound && index < itemCount)
            [_items[index] setSelected:NO];
    }
}

/*!
    Returns \c YES if the collection view is
    selectable, and \c NO otherwise.
*/
- (BOOL)isSelectable
{
    return _isSelectable;
}

/*!
    Sets whether the user may have no items selected. If YES, mouse clicks not on any item will empty the current selection. The first item will also start off as selected.
    @param shouldAllowMultipleSelection \c YES allows the user to select multiple items
*/
- (void)setAllowsEmptySelection:(BOOL)shouldAllowEmptySelection
{
    _allowsEmptySelection = shouldAllowEmptySelection;
}

/*!
    Returns \c YES if the user can select no items, \c NO otherwise.
*/
- (BOOL)allowsEmptySelection
{
    return _allowsEmptySelection;
}

/*!
    Sets whether the user can select multiple items.
    @param shouldAllowMultipleSelection \c YES allows the user to select multiple items
*/
- (void)setAllowsMultipleSelection:(BOOL)shouldAllowMultipleSelection
{
    _allowsMultipleSelection = shouldAllowMultipleSelection;
}

/*!
    Returns \c YES if the user can select multiple items, \c NO otherwise.
*/
- (BOOL)allowsMultipleSelection
{
    return _allowsMultipleSelection;
}

/*!
    Sets the selected items based on the provided indices.
    @param anIndexSet the set of items to be selected
*/
- (void)setSelectionIndexes:(CPIndexSet)anIndexSet
{
    if (!anIndexSet)
        anIndexSet = [CPIndexSet indexSet];
    if (!_isSelectable || [_selectionIndexes isEqual:anIndexSet])
        return;

    var index = CPNotFound,
        itemCount = [_items count];

    // Be wary of invalid selection ranges since setContent: does not clear selection indexes.
    while ((index = [_selectionIndexes indexGreaterThanIndex:index]) !== CPNotFound && index < itemCount)
        [_items[index] setSelected:NO];

    _selectionIndexes = anIndexSet;

    var index = CPNotFound;

    while ((index = [_selectionIndexes indexGreaterThanIndex:index]) !== CPNotFound)
        [_items[index] setSelected:YES];

    var binderClass = [[self class] _binderClassForBinding:@"selectionIndexes"];
    [[binderClass getBinding:@"selectionIndexes" forObject:self] reverseSetValueFor:@"selectionIndexes"];

    if ([_delegate respondsToSelector:@selector(collectionViewDidChangeSelection:)])
        [_delegate collectionViewDidChangeSelection:self];
}

/*!
    Returns a set of the selected indices.
*/
- (CPIndexSet)selectionIndexes
{
    return [_selectionIndexes copy];
}

- (void)reloadContent
{
    [self reloadContentCachingRemovedItems:YES];
}

/* @ignore */
- (void)reloadContentCachingRemovedItems:(BOOL)shouldCache
{
    // Remove current views
    var count = _items.length;

    while (count--)
    {
        [[_items[count] view] removeFromSuperview];
        [_items[count] setSelected:NO];

        if (shouldCache)
            _cachedItems.push(_items[count]);
    }

    _items = [];

    if (!_itemPrototype)
        return;

    var index = 0;

    count = _content.length;

    for (; index < count; ++index)
    {
        _items.push([self newItemForRepresentedObject:_content[index]]);

        [self addSubview:[_items[index] view]];
    }

    index = CPNotFound;
    // Be wary of invalid selection ranges since setContent: does not clear selection indexes.
    while ((index = [_selectionIndexes indexGreaterThanIndex:index]) != CPNotFound && index < count)
        [_items[index] setSelected:YES];

    [self tileIfNeeded:NO];
}

- (void)resizeSubviewsWithOldSize:(CPSize)oldBoundsSize
{
    // Desactivate subviews autoresizing
}

- (void)resizeWithOldSuperviewSize:(CPSize)oldBoundsSize
{
    if (_lockResizing)
        return;

    _lockResizing = YES;

    [self tile];

    _lockResizing = NO;
}

- (void)tile
{
    [self tileIfNeeded:!_uniformSubviewsResizing];
}

- (void)tileIfNeeded:(BOOL)lazyFlag
{
    var frameSize = CGSizeMakeCopy([[self superview] frameSize]),
        itemSize = CGSizeMakeZero(),
        colsRowsCount = [];

        oldNumberOfColumns = _numberOfColumns,
        oldNumberOfRows = _numberOfRows,
        oldItemSize = _itemSize,
        storedFrameSize = _storedFrameSize;

    [self _updateMinMaxItemSizeIfNeeded];

    [self getFrameSize:frameSize itemSize:itemSize columnsRowsCount:colsRowsCount];

    //CPLog.debug("frameSize="+CPStringFromSize(frameSize) + "itemSize="+CPStringFromSize(itemSize) + " ncols=" +  colsRowsCount[0] +" nrows="+ colsRowsCount[1]+" displayCount="+ colsRowsCount[2]);

    _numberOfColumns = colsRowsCount[0];
    _numberOfRows = colsRowsCount[1];
    _itemSize = itemSize;
    _storedFrameSize = frameSize;

    [self setFrameSize:frameSize];

    //CPLog.debug("OLD " + oldNumberOfColumns + " NEW " + _numberOfColumns);
    if (!lazyFlag ||
        _numberOfColumns !== oldNumberOfColumns ||
        _numberOfRows !== oldNumberOfRows ||
        !CGSizeEqualToSize(_itemSize, oldItemSize))

        [self displayItems:_items frameSize:frameSize itemSize:_itemSize columns:_numberOfColumns rows:_numberOfRows count:colsRowsCount[2]];
}

- (void)getFrameSize:({CGSize})aSuperviewSize itemSize:({CGSize})anItemSize columnsRowsCount:({CPArray})colsRowsCount
{
    var width               = aSuperviewSize.width,
        height              = aSuperviewSize.height,
        itemSize            = CGSizeMakeCopy(_minItemSize),
        maxItemSizeWidth    = _maxItemSize.width,
        maxItemSizeHeight   = _maxItemSize.height,
        itemsCount          = [_items count],
        numberOfRows,
        numberOfColumns;

    numberOfColumns = FLOOR(width / itemSize.width);

    if (maxItemSizeWidth == 0)
        numberOfColumns = MIN(numberOfColumns, _maxNumberOfColumns);

    if (_maxNumberOfColumns > 0)
        numberOfColumns = MIN(MIN(_maxNumberOfColumns, itemsCount), numberOfColumns);

    numberOfColumns = MAX(1.0, numberOfColumns);

    itemSize.width = FLOOR(width / numberOfColumns);

    if (maxItemSizeWidth > 0)
    {
        itemSize.width = MIN(maxItemSizeWidth, itemSize.width);

        if (numberOfColumns == 1)
            itemSize.width = MIN(maxItemSizeWidth, width);
    }

    numberOfRows = MAX(1.0 , MIN(CEIL(itemsCount / numberOfColumns), _maxNumberOfRows));

    height = MAX(height, numberOfRows * (_minItemSize.height + _verticalMargin));

    var itemSizeHeight = FLOOR(height / numberOfRows);

    if (maxItemSizeHeight > 0)
        itemSizeHeight = MIN(itemSizeHeight, maxItemSizeHeight);

    anItemSize.height = MAX(_minItemSize.height, itemSizeHeight);
    anItemSize.width = MAX(_minItemSize.width, itemSize.width);

    aSuperviewSize.width = MAX(width, _minItemSize.width);
    aSuperviewSize.height = height;
    colsRowsCount[0] = numberOfColumns;
    colsRowsCount[1] = numberOfRows;
    colsRowsCount[2] = MIN(itemsCount, numberOfColumns * numberOfRows);
}

- (void)displayItems:(CPArray)displayItems frameSize:(CGSize)aFrameSize itemSize:(CGSize)anItemSize columns:(CPInteger)numberOfColumns rows:(CPInteger)numberOfRows count:(CPInteger)displayCount
{
//    CPLog.debug("DISPLAY ITEMS " + numberOfColumns + " " +  numberOfRows);

    var horizontalMargin = _uniformSubviewsResizing ? FLOOR((aFrameSize.width - numberOfColumns * anItemSize.width) / (numberOfColumns + 1)) : 0;

    var x = horizontalMargin,
        y = -anItemSize.height;

    [displayItems enumerateObjectsUsingBlock:function(item, idx, stop)
    {
        var view = [item view];

        if (idx >= displayCount)
        {
            [view setFrameOrigin:CGPointMake(-anItemSize.width, -anItemSize.height)];
            return;
        }

        if (idx % numberOfColumns == 0)
        {
            x = horizontalMargin;
            y += _verticalMargin + anItemSize.height;
        }

        [view setFrameOrigin:CGPointMake(x, y)];
        [view setFrameSize:anItemSize];

        x += anItemSize.width + horizontalMargin;
    }];
}

- (void)_updateMinMaxItemSizeIfNeeded
{
    if (!_needsMinMaxItemSizeUpdate)
        return;

    var prototypeView;

    if (_itemPrototype && (prototypeView = [_itemPrototype view]))
    {
        if (_minItemSize.width == 0)
            _minItemSize.width = [prototypeView frameSize].width;

        if (_minItemSize.height == 0)
            _minItemSize.height = [prototypeView frameSize].height;

        if (_maxItemSize.height == 0 && !([prototypeView autoresizingMask] & CPViewHeightSizable))
            _maxItemSize.height = [prototypeView frameSize].height;

        if (_maxItemSize.width == 0 && !([prototypeView autoresizingMask] & CPViewWidthSizable))
            _maxItemSize.width = [prototypeView frameSize].width;

        _needsMinMaxItemSizeUpdate = NO;
    }
}

// Laying Out the Collection View
/*!
    Sets the maximum number of rows.
    @param aMaxNumberOfRows the new maximum number of rows
*/
- (void)setMaxNumberOfRows:(unsigned)aMaxNumberOfRows
{
    if (_maxNumberOfRows == aMaxNumberOfRows)
        return;

    _maxNumberOfRows = aMaxNumberOfRows;

    [self tile];
}

/*!
    Returns the maximum number of rows.
*/
- (unsigned)maxNumberOfRows
{
    return _maxNumberOfRows;
}

/*!
    Sets the maximum number of columns.
    @param aMaxNumberOfColumns the new maximum number of columns
*/
- (void)setMaxNumberOfColumns:(unsigned)aMaxNumberOfColumns
{
    if (_maxNumberOfColumns == aMaxNumberOfColumns)
        return;

    _maxNumberOfColumns = aMaxNumberOfColumns;

    [self tile];
}

/*!
    Returns the maximum number of columns
*/
- (unsigned)maxNumberOfColumns
{
    return _maxNumberOfColumns;
}

/*!
    Returns the current number of rows
*/
- (unsigned)numberOfRows
{
    return _numberOfRows;
}

/*!
    Returns the current number of columns
*/

- (unsigned)numberOfColumns
{
    return _numberOfColumns;
}

/*!
    Sets the minimum size for an item
    @param aSize the new minimum item size
*/
- (void)setMinItemSize:(CGSize)aSize
{
    if (aSize === nil || aSize === undefined)
        [CPException raise:CPInvalidArgumentException reason:"Invalid value provided for minimum size"];

    if (CGSizeEqualToSize(_minItemSize, aSize))
        return;

    _minItemSize = CGSizeMakeCopy(aSize);

    if (CGSizeEqualToSize(_minItemSize, CGSizeMakeZero()))
        _needsMinMaxItemSizeUpdate = YES;

    [self tile];
}

/*!
    Returns the current minimum item size
*/
- (CGSize)minItemSize
{
    return _minItemSize;
}

/*!
    Sets the maximum item size.
    @param aSize the new maximum item size
*/
- (void)setMaxItemSize:(CGSize)aSize
{
    if (CGSizeEqualToSize(_maxItemSize, aSize))
        return;

    _maxItemSize = CGSizeMakeCopy(aSize);

//    if (_maxItemSize.width == 0 || _maxItemSize.height == 0)
//        _needsMinMaxItemSizeUpdate = YES;

    [self tile];
}

/*!
    Returns the current maximum item size.
*/
- (CGSize)maxItemSize
{
    return _maxItemSize;
}

- (void)setBackgroundColors:(CPArray)backgroundColors
{
    if (_backgroundColors === backgroundColors)
        return;

    _backgroundColors = backgroundColors;

    if (!_backgroundColors)
        _backgroundColors = [[CPColor whiteColor]];

    if ([_backgroundColors count] === 1)
        [self setBackgroundColor:_backgroundColors[0]];

    else
        [self setBackgroundColor:nil];

    [self setNeedsDisplay:YES];
}

- (CPArray)backgroundColors
{
    return _backgroundColors;
}

- (void)bind:(CPString)binding toObject:(id)observableController withKeyPath:(CPString)keyPath options:(CPDictionary )options
{
    if (binding == CPContentBinding)
        [observableController addObserver:self forKeyPath:keyPath options:CPKeyValueObservingOptionOld|CPKeyValueObservingOptionNew context:"content"];

    [super bind:binding toObject:observableController withKeyPath:keyPath options:options];
}

- (void)observeValueForKeyPath:(CPString)keyPath ofObject:(id)object change:(CPDictionary)change context:(id)context
{
    var newObjects = [change objectForKey:CPKeyValueChangeNewKey];
    var kind = [change objectForKey:CPKeyValueChangeKindKey];
    CPLog.debug("kind " + kind + " " + [newObjects description]);
}


- (void)mouseUp:(CPEvent)anEvent
{
    if ([_selectionIndexes count] && [anEvent clickCount] == 2 && [_delegate respondsToSelector:@selector(collectionView:didDoubleClickOnItemAtIndex:)])
        [_delegate collectionView:self didDoubleClickOnItemAtIndex:[_selectionIndexes firstIndex]];
}

- (void)mouseDown:(CPEvent)anEvent
{
    _mouseDownEvent = anEvent;

    var location = [self convertPoint:[anEvent locationInWindow] fromView:nil],
        index = [self _indexAtPoint:location];

    if (index >= 0 && index < _items.length)
    {
        if (_allowsMultipleSelection && ([anEvent modifierFlags] & CPPlatformActionKeyMask || [anEvent modifierFlags] & CPShiftKeyMask))
        {
            if ([anEvent modifierFlags] & CPPlatformActionKeyMask)
            {
                var indexes = [_selectionIndexes copy];

                if ([indexes containsIndex:index])
                    [indexes removeIndex:index];
                else
                    [indexes addIndex:index];
            }
            else if ([anEvent modifierFlags] & CPShiftKeyMask)
            {
                var firstSelectedIndex = [[self selectionIndexes] firstIndex],
                    newSelectedRange = nil;

                if (index < firstSelectedIndex)
                    newSelectedRange = CPMakeRange(index, (firstSelectedIndex - index) + 1);
                else
                    newSelectedRange = CPMakeRange(firstSelectedIndex, (index - firstSelectedIndex) + 1);

                indexes = [[self selectionIndexes] copy];
                [indexes addIndexesInRange:newSelectedRange];
            }
        }
        else
            indexes = [CPIndexSet indexSetWithIndex:index];

        [self setSelectionIndexes:indexes];

        // TODO Is it allowable for collection view items to become the first responder? In that case they
        // may have become that at this point by virtue of CPWindow's sendEvent: mouse down handling, and
        // the following line will rudely snatch it away from them. For most cases though, clicking on an
        // item should naturally make the collection view the first responder so that keyboard navigation
        // is enabled.
        [[self window] makeFirstResponder:self];
    }
    else if (_allowsEmptySelection)
        [self setSelectionIndexes:[CPIndexSet indexSet]];
}

- (void)mouseDragged:(CPEvent)anEvent
{
    // Don't crash if we never registered the intial click.
    if (!_mouseDownEvent)
        return;

    var locationInWindow = [anEvent locationInWindow],
        mouseDownLocationInWindow = [_mouseDownEvent locationInWindow];

    // FIXME: This is because Safari's drag hysteresis is 3px x 3px
    if ((ABS(locationInWindow.x - mouseDownLocationInWindow.x) < 3) &&
        (ABS(locationInWindow.y - mouseDownLocationInWindow.y) < 3))
        return;

    if (![_delegate respondsToSelector:@selector(collectionView:dragTypesForItemsAtIndexes:)])
        return;

    // If we don't have any selected items, we've clicked away, and thus the drag is meaningless.
    if (![_selectionIndexes count])
        return;

    if ([_delegate respondsToSelector:@selector(collectionView:canDragItemsAtIndexes:withEvent:)] &&
        ![_delegate collectionView:self canDragItemsAtIndexes:_selectionIndexes withEvent:_mouseDownEvent])
        return;

    // Set up the pasteboard
    var dragTypes = [_delegate collectionView:self dragTypesForItemsAtIndexes:_selectionIndexes];

    [[CPPasteboard pasteboardWithName:CPDragPboard] declareTypes:dragTypes owner:self];

    if (!_itemForDragging)
        _itemForDragging = [self newItemForRepresentedObject:_content[[_selectionIndexes firstIndex]]];
    else
        [_itemForDragging setRepresentedObject:_content[[_selectionIndexes firstIndex]]];

    var view = [_itemForDragging view];

    [view setFrameSize:_itemSize];
    [view setAlphaValue:0.7];

    [self dragView:view
        at:[[_items[[_selectionIndexes firstIndex]] view] frame].origin
        offset:CGSizeMakeZero()
        event:_mouseDownEvent
        pasteboard:nil
        source:self
        slideBack:YES];
}

/*!
    Places the selected items on the specified pasteboard. The items are requested from the collection's delegate.
    @param aPasteboard the pasteboard to put the items on
    @param aType the format the pasteboard data
*/
- (void)pasteboard:(CPPasteboard)aPasteboard provideDataForType:(CPString)aType
{
    [aPasteboard setData:[_delegate collectionView:self dataForItemsAtIndexes:_selectionIndexes forType:aType] forType:aType];
}

// Cappuccino Additions

/*!
    Sets the collection view's vertical spacing between elements.
    @param aVerticalMargin the number of pixels to place between elements
*/

- (void)setVerticalMargin:(float)aVerticalMargin
{
    if (_verticalMargin == aVerticalMargin)
        return;

    _verticalMargin = aVerticalMargin;

    [self tile];
}

/*!
    Gets the collection view's current vertical spacing between elements.
*/

- (float)verticalMargin
{
    return _verticalMargin;
}

/*!
    Sets the collection view's delegate
    @param aDelegate the new delegate
*/
- (void)setDelegate:(id)aDelegate
{
    _delegate = aDelegate;
}

/*!
    Returns the collection view's delegate
*/
- (id)delegate
{
    return _delegate;
}

/*!
    @ignore
*/
- (CPMenu)menuForEvent:(CPEvent)theEvent
{
    if (![[self delegate] respondsToSelector:@selector(collectionView:menuForItemAtIndex:)])
        return [super menuForEvent:theEvent];

    var location = [self convertPoint:[theEvent locationInWindow] fromView:nil],
        index = [self _indexAtPoint:location];

    return [_delegate collectionView:self menuForItemAtIndex:index];
}

- (int)_indexAtPoint:(CGPoint)thePoint
{
    var row = FLOOR(thePoint.y / (_itemSize.height + _verticalMargin)),
        column = FLOOR(thePoint.x / (_itemSize.width + _horizontalMargin));

    return row * _numberOfColumns + column;
}

- (CPCollectionViewItem)itemAtIndex:(unsigned)anIndex
{
    return [_items objectAtIndex:anIndex];
}

- (CGRect)frameForItemAtIndex:(unsigned)anIndex
{
    return [[[self itemAtIndex:anIndex] view] frame];
}

- (CGRect)frameForItemsAtIndexes:(CPIndexSet)anIndexSet
{
    var indexArray = [],
        frame = CGRectNull;

    [anIndexSet getIndexes:indexArray maxCount:-1 inIndexRange:nil];

    var index = 0,
        count = [indexArray count];

    for (; index < count; ++index)
        frame = CGRectUnion(frame, [self frameForItemAtIndex:indexArray[index]]);

    return frame;
}

@end

@implementation CPCollectionView (KeyboardInteraction)

- (void)_modifySelectionWithNewIndex:(int)anIndex direction:(int)aDirection expand:(BOOL)shouldExpand
{
    anIndex = MIN(MAX(anIndex, 0), [[self items] count] - 1);

    if (_allowsMultipleSelection && shouldExpand)
    {
        var indexes = [_selectionIndexes copy],
            bottomAnchor = [indexes firstIndex],
            topAnchor = [indexes lastIndex];

        // if the direction is backward (-1) check with the bottom anchor
        if (aDirection === -1)
            [indexes addIndexesInRange:CPMakeRange(anIndex, bottomAnchor - anIndex + 1)];
        else
            [indexes addIndexesInRange:CPMakeRange(topAnchor, anIndex -  topAnchor + 1)];
    }
    else
        indexes = [CPIndexSet indexSetWithIndex:anIndex];

    [self setSelectionIndexes:indexes];
    [self _scrollToSelection];
}

- (void)_scrollToSelection
{
    var frame = [self frameForItemsAtIndexes:[self selectionIndexes]];

    if (!CGRectIsNull(frame))
        [self scrollRectToVisible:frame];
}

- (void)moveLeft:(id)sender
{
    var index = [[self selectionIndexes] firstIndex];
    if (index === CPNotFound)
        index = [[self items] count];

    [self _modifySelectionWithNewIndex:index - 1 direction:-1 expand:NO];
}

- (void)moveLeftAndModifySelection:(id)sender
{
    var index = [[self selectionIndexes] firstIndex];
    if (index === CPNotFound)
        index = [[self items] count];

    [self _modifySelectionWithNewIndex:index - 1 direction:-1 expand:YES];
}

- (void)moveRight:(id)sender
{
    [self _modifySelectionWithNewIndex:[[self selectionIndexes] lastIndex] + 1 direction:1 expand:NO];
}

- (void)moveRightAndModifySelection:(id)sender
{
    [self _modifySelectionWithNewIndex:[[self selectionIndexes] lastIndex] + 1 direction:1 expand:YES];
}

- (void)moveDown:(id)sender
{
    [self _modifySelectionWithNewIndex:[[self selectionIndexes] lastIndex] + [self numberOfColumns] direction:1 expand:NO];
}

- (void)moveDownAndModifySelection:(id)sender
{
    [self _modifySelectionWithNewIndex:[[self selectionIndexes] lastIndex] + [self numberOfColumns] direction:1 expand:YES];
}

- (void)moveUp:(id)sender
{
    var index = [[self selectionIndexes] firstIndex];
    if (index == CPNotFound)
        index = [[self items] count];

    [self _modifySelectionWithNewIndex:index - [self numberOfColumns] direction:-1 expand:NO];
}

- (void)moveUpAndModifySelection:(id)sender
{
    var index = [[self selectionIndexes] firstIndex];
    if (index == CPNotFound)
        index = [[self items] count];

    [self _modifySelectionWithNewIndex:index - [self numberOfColumns] direction:-1 expand:YES];
}

- (void)deleteBackward:(id)sender
{
    if ([[self delegate] respondsToSelector:@selector(collectionView:shouldDeleteItemsAtIndexes:)])
    {
        [[self delegate] collectionView:self shouldDeleteItemsAtIndexes:[self selectionIndexes]];

        var index = [[self selectionIndexes] firstIndex];
        if (index > [[self content] count] - 1)
            [self setSelectionIndexes:[CPIndexSet indexSetWithIndex:[[self content] count] - 1]];

        [self _scrollToSelection];
        [self setNeedsDisplay:YES];
    }
}

- (void)keyDown:(CPEvent)anEvent
{
    [self interpretKeyEvents:[anEvent]];
}

- (void)setAutoresizingMask:(int)aMask
{
    [super setAutoresizingMask:0];
}

@end

@implementation CPCollectionView (Deprecated)

- (CGRect)rectForItemAtIndex:(int)anIndex
{
    _CPReportLenientDeprecation([self class], _cmd, @selector(frameForItemAtIndex:));

    // Don't re-compute anything just grab the current frame
    // This allows subclasses to override tile without messing this up.
    return [self frameForItemAtIndex:anIndex];
}

- (CGRect)rectForItemsAtIndexes:(CPIndexSet)anIndexSet
{
    _CPReportLenientDeprecation([self class], _cmd, @selector(frameForItemsAtIndexes:));

    return [self frameForItemsAtIndexes:anIndexSet];
}

@end

var CPCollectionViewMinItemSizeKey              = @"CPCollectionViewMinItemSizeKey",
    CPCollectionViewMaxItemSizeKey              = @"CPCollectionViewMaxItemSizeKey",
    CPCollectionViewVerticalMarginKey           = @"CPCollectionViewVerticalMarginKey",
    CPCollectionViewMaxNumberOfRowsKey          = @"CPCollectionViewMaxNumberOfRowsKey",
    CPCollectionViewMaxNumberOfColumnsKey       = @"CPCollectionViewMaxNumberOfColumnsKey",
    CPCollectionViewSelectableKey               = @"CPCollectionViewSelectableKey",
    CPCollectionViewAllowsMultipleSelectionKey  = @"CPCollectionViewAllowsMultipleSelectionKey",
    CPCollectionViewBackgroundColorsKey         = @"CPCollectionViewBackgroundColorsKey";


@implementation CPCollectionView (CPCoding)

- (id)initWithCoder:(CPCoder)aCoder
{
    self = [super initWithCoder:aCoder];

    if (self)
    {
        _minItemSize = [aCoder decodeSizeForKey:CPCollectionViewMinItemSizeKey];
        _maxItemSize = [aCoder decodeSizeForKey:CPCollectionViewMaxItemSizeKey];

        _maxNumberOfRows = [aCoder decodeIntForKey:CPCollectionViewMaxNumberOfRowsKey];
        _maxNumberOfColumns = [aCoder decodeIntForKey:CPCollectionViewMaxNumberOfColumnsKey];

        _verticalMargin = [aCoder decodeFloatForKey:CPCollectionViewVerticalMarginKey];

        _isSelectable = [aCoder decodeBoolForKey:CPCollectionViewSelectableKey];
        _allowsMultipleSelection = [aCoder decodeBoolForKey:CPCollectionViewAllowsMultipleSelectionKey];

        [self setBackgroundColors:[aCoder decodeObjectForKey:CPCollectionViewBackgroundColorsKey]];

        [self _init];
    }

    return self;
}

- (void)encodeWithCoder:(CPCoder)aCoder
{
    [super encodeWithCoder:aCoder];

    if (!CGSizeEqualToSize(_minItemSize, CGSizeMakeZero()))
      [aCoder encodeSize:_minItemSize forKey:CPCollectionViewMinItemSizeKey];

    if (!CGSizeEqualToSize(_maxItemSize, CGSizeMakeZero()))
      [aCoder encodeSize:_maxItemSize forKey:CPCollectionViewMaxItemSizeKey];

    [aCoder encodeInt:_maxNumberOfRows forKey:CPCollectionViewMaxNumberOfRowsKey];
    [aCoder encodeInt:_maxNumberOfColumns forKey:CPCollectionViewMaxNumberOfColumnsKey];

    [aCoder encodeBool:_isSelectable forKey:CPCollectionViewSelectableKey];
    [aCoder encodeBool:_allowsMultipleSelection forKey:CPCollectionViewAllowsMultipleSelectionKey];

    [aCoder encodeFloat:_verticalMargin forKey:CPCollectionViewVerticalMarginKey];

    [aCoder encodeObject:_backgroundColors forKey:CPCollectionViewBackgroundColorsKey];
}

@end
