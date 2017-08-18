import QtQuick 2.0

ShaderEffect{
    width: 640 ;height: 320;
    transform: Rotation { origin.x: width/2; origin.y: height/2; angle: 180}
    property real iGlobalTime: 0.0
    SequentialAnimation on iGlobalTime {
        NumberAnimation { to: 10.0; duration: 10000 }
        NumberAnimation { to: 0.0; duration: 0 }
        loops:Animation.Infinite
    }
    fragmentShader:  "
    uniform float iGlobalTime;
    varying highp vec2 qt_TexCoord0;


vec3 firePalette(float i){

    float T = 1400. + 1300.*i; // Temperature range (in Kelvin).
    vec3 L = vec3(7.4, 5.6, 4.4); // Red, green, blue wavelengths (in hundreds of nanometers).
    L = pow(L,vec3(5.0)) * (exp(1.43876719683e5/(T*L))-1.0);
    return 1.0-exp(-5e8/L);
}

/*
vec3 firePalette(float i){

    float T = 1400. + 1300.*i; // Temperature range (in Kelvin).
    // Hardcode red, green and blue wavelengths (in hundreds of nanometers).
    vec3 L = (exp(vec3(19442.7999572, 25692.271372, 32699.2544734)/T)-1.0);

    return 1.0-exp(-vec3(22532.6051122, 90788.296915, 303184.239775)*2.*.5/L);
}
*/

// Hash function. This particular one probably doesn't disperse things quite as nicely as some
// of the others around, but it's compact, and seems to work.

vec3 hash33(vec3 p){

    float n = sin(dot(p, vec3(7, 157, 113)));
    return fract(vec3(2097152, 262144, 32768)*n);
}

// 3D Voronoi: Obviously, this is just a rehash of IQ's original.

float voronoi(vec3 p){

    vec3 b, r, g = floor(p);
    p = fract(p);
    float d = 1.;

    // I've unrolled one of the loops. GPU architecture is a mystery to me, but I'm aware
    // they're not fond of nesting, branching, etc. My laptop GPU seems to hate everything,
    // including multiple loops. If it were a person, we wouldn't hang out.
    for(int j = -1; j <= 1; j++) {
        for(int i = -1; i <= 1; i++) {

            b = vec3(i, j, -1);
            r = b - p + hash33(g+b);
            d = min(d, dot(r,r));

            b.z = 0.0;
            r = b - p + hash33(g+b);
            d = min(d, dot(r,r));

            b.z = 1.;
            r = b - p + hash33(g+b);
            d = min(d, dot(r,r));

        }
    }

    return d; // Range: [0, 1]
}

// Standard fBm function with some time dialation to give a parallax
// kind of effect. In other words, the position and time frequencies
// are changed at different rates from layer to layer.
//
float noiseLayers(in vec3 p) {


    vec3 t = vec3(0., 0., p.z+iGlobalTime*1.5);

    const int iter = 5; // Just five layers is enough.
    float tot = 0., sum = 0., amp = 1.; // Total, sum, amplitude.

    for (int i = 0; i < iter; i++) {
        tot += voronoi(p + t) * amp; // Add the layer to the total.
        p *= 2.0; // Position multiplied by two.
        t *= 1.5; // Time multiplied by less than two.
        sum += amp; // Sum of amplitudes.
        amp *= 0.5; // Decrease successive layer amplitude, as normal.
    }

    return tot/sum; // Range: [0, 1].
}

void main()
{
    // Screen coordinates.
    vec2 uv = qt_TexCoord0.xy * qt_TexCoord0.y * 0.5;
    // Shifting the central position around, just a little, to simulate a
    // moving camera, albeit a pretty lame one.
    uv += vec2(sin(iGlobalTime*0.5)*0.25, cos(iGlobalTime*0.5)*0.125);

    // Constructing the unit ray.
    vec3 rd = normalize(vec3(uv.x, uv.y, 3.1415926535898/8.));

    // Rotating the ray about the XY plane, to simulate a rolling camera.
    float cs = cos(iGlobalTime*0.25), si = sin(iGlobalTime*0.25);

    rd.xy = rd.xy*mat2(cs, -si, si, cs);

    // Passing a unit ray multiple into the Voronoi layer function, which
    // is nothing more than an fBm setup with some time dialation.
    float c = noiseLayers(rd*2.);

    // Optional: Adding a bit of random noise for a subtle dust effect.
    c = max(c + dot(hash33(rd)*2.-1., vec3(0.015)), 0.);

    // Coloring:

    // Nebula.
    c *= sqrt(c)*1.5;
    vec3 col = firePalette(c); // Palettization.

    col = mix(col, col.zyx*0.15+c*0.85, min(pow(dot(rd.xy, rd.xy)*1.2, 1.5), 1.)); // Color dispersion.
    col = pow(col, vec3(1.5));

    gl_FragColor = vec4(sqrt(clamp(col, 0.0, 1.0)), 1.0);
}
    "
}