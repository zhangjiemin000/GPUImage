varying highp vec2 textureCoordinate;

uniform sampler2D inputImageTexture;

const highp vec2 sampleDivisor = vec2(0.5, 0.5);

void main()
{
    //mod = n-d*INT(n/d), d < 1, so, n-(mod(n,d))  = d*INT(n/d), so , position is determined by n/d, and step is d
    highp vec2 samplePos = textureCoordinate - mod(textureCoordinate, sampleDivisor);

    gl_FragColor = texture2D(inputImageTexture, samplePos );
}