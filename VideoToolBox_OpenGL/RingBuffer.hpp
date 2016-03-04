//
//  RingBufferDataRef.hpp
//  VideoToolBox_OpenGL
//
//  Created by Cong Ku on 12/10/15.
//  Copyright © 2015 Cong Ku. All rights reserved.
//

#ifndef RingBufferDataRef_hpp
#define RingBufferDataRef_hpp

#import <Foundation/Foundation.h>
#include <queue>


template <typename UserData_T>
struct RingBufferDataRef {
    uint8_t* head;
    uint32_t size;
    UserData_T userData;
};

template <typename UserData_T>
class RingBuffer {
private:
    uint8_t* _buffer;
    uint32_t _bufferCapacity;
    uint32_t _bufferCount;
    
    uint32_t _bufferSize;
    uint8_t* _bufferHead;
    uint8_t* _bufferTail;
    std::queue<RingBufferDataRef<UserData_T>> _bufferDataRefQueue;
public:
    RingBuffer(uint8_t* pBuffer, uint32_t pBufferCapacity)
    {
        _buffer = pBuffer;
        _bufferCapacity = pBufferCapacity;
        _bufferCount = 0;
        
        _bufferSize = 0;
        _bufferHead = _buffer;
        _bufferTail = _buffer;
    }

    ~RingBuffer()
    {
        
    }
    
    int bufferSize() const
    {
        return _bufferSize;
    }
    
    int bufferCount() const
    {
        return _bufferCount;
    }
    
    bool isBufferEmpty() const
    {
        return _bufferDataRefQueue.empty();
    }
    
    RingBufferDataRef<UserData_T>& back() const
    {
        return _bufferDataRefQueue.back();
    }
    
    RingBufferDataRef<UserData_T>& front()
    {
        return _bufferDataRefQueue.front();
    }
    
    bool pushBack(uint8_t* pData, uint32_t pSize, UserData_T pUserData)
    {
        RingBufferDataRef<UserData_T> dataRef;
        bool availableFromHead;
        
        if (isBufferAvailable(pSize, availableFromHead))
        {
            if (availableFromHead) {
                memcpy(_buffer, pData, pSize);
                dataRef.head = _buffer;
                _bufferSize += pSize + (_bufferCapacity - (_bufferTail - _buffer));
                _bufferTail = _buffer + pSize;
            }
            else
            {
                memcpy(_bufferTail, pData, pSize);
                dataRef.head = _bufferTail;
                _bufferSize += pSize;
                _bufferTail += pSize;
            }
            
            dataRef.size = pSize;
            dataRef.userData = pUserData;
            _bufferDataRefQueue.push(dataRef);
            
            ++_bufferCount;
            
            return true;
        }
        
        return false;
    }
    
    void popFront()
    {
        RingBufferDataRef<UserData_T> frontDataRef = _bufferDataRefQueue.front();
        _bufferDataRefQueue.pop();
        if (_bufferDataRefQueue.empty())
        {
            _bufferSize = 0;
            _bufferHead = _buffer;
            _bufferTail = _buffer;
            return;
        }
        
        
        RingBufferDataRef<UserData_T> newFrontDataRef = _bufferDataRefQueue.front();
        
        if (newFrontDataRef.head == _buffer)
        {
            _bufferSize -= _bufferCapacity - (frontDataRef.head - _buffer);
        }
        else
        {
            _bufferSize -= frontDataRef.size;
        }
        
        _bufferHead = newFrontDataRef.head;
        --_bufferCount;
    }
    
    bool isBufferAvailable(uint32_t pSize)
    {
        if (_bufferCapacity - _bufferSize > pSize)
        {
            if (_bufferTail >= _bufferHead)
            {
                if ((_bufferCapacity - (_bufferTail - _buffer)) > pSize || (_bufferHead - _buffer) > pSize) {
                    return true;
                }
            }
            else if (_bufferHead - _bufferTail > pSize)
            {
                return true;
            }
        }
        return false;
    }
    
    bool isBufferAvailable(uint32_t pSize, bool& pAvailableFromHead)
    {
        pAvailableFromHead = false;
        if (_bufferCapacity - _bufferSize > pSize)
        {
            if (_bufferTail >= _bufferHead)
            {
                if ((_bufferCapacity - (_bufferTail - _buffer)) > pSize )
                {
                    return true;
                }
                else if ((_bufferHead - _buffer) > pSize)
                {
                    pAvailableFromHead = true;
                    return true;
                }
                return false;
            }
            else if (_bufferHead - _bufferTail > pSize)
            {
                return true;
            }
        }
        return false;
    }
    
    void flush()
    {
        _bufferCount = 0;
        _bufferSize = 0;
        _bufferHead = _buffer;
        _bufferTail = _buffer;
        
        std::queue<RingBufferDataRef<UserData_T>> empty;
        std::swap(_bufferDataRefQueue, empty);
    }
};
#endif /* RingBufferDataRef_hpp */
