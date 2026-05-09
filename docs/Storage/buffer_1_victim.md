# Buffer Read

## 页面读入

```c
heapgetpage
	ReadBufferExtended
		ReadBuffer_common
			BufferAlloc
				PinBuffer
				StartBufferIO*
			smgrread*
			TerminateBufferIO*
			
			return BufferDescriptorGetBuffer(bufHdr);
```

## 页面置换

- Clock Sweep

