using System;
using System.IO;
using System.Security.Cryptography;

public class CRC16 : HashAlgorithm
{
    private const uint UCHAR_MAX = byte.MaxValue;
    private const int CHAR_BIT = 8;
    private const uint CRCPOLY = 0xA001;
    private uint[] crctable = new uint[(UCHAR_MAX + 1)];

    private uint crcResult;

    private void MakeCrcTable()
    {
        for (uint i = 0; i <= UCHAR_MAX; i++)
        {
            uint r = i;
            for (uint j = 0; j < CHAR_BIT; j++)
            {
                if ((r & 1) != 0)
                {
                    r = (r >> 1) ^ CRCPOLY;
                }
                else
                {
                    r >>= 1;
                }
            }
            crctable[i] = r;
        }
    }

    public CRC16()
    {
        MakeCrcTable();
        crcResult = 0;
    }

    private uint UPDATE_CRC(uint crc, byte c)
    {
        return (crctable[((crc ^ c) & 0xFF)] ^ (crc >> CHAR_BIT));
    }

    public override void Initialize()
    {
        crcResult = 0;
    }

    protected override void HashCore(byte[] array, int ibStart, int cbSize)
    {
        while (cbSize-- > 0)
        {
            crcResult = UPDATE_CRC(crcResult, array[ibStart++]);
        }
    }

    protected override byte[] HashFinal()
    {
        byte[] returnValue = new byte[] {
            (byte)((crcResult >> 24) & 0xff),
            (byte)((crcResult >> 16) & 0xff),
            (byte)((crcResult >>  8) & 0xff),
            (byte)( crcResult        & 0xff)
        };
        return returnValue;
    }
}
